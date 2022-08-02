#include <ctype.h>
#include <stdarg.h>

#include "txtquad/extras/block.h"
#include "acg/control.h"
#include "acg/rand.h"
#include "acg/uid.h"
#include "acg/istr.h"
#include "acg/screen.h"

#define DEL_REP_S .05f
#define DEL_DEL_S .1f

#ifdef  EDGE_SOLID
	#define EDGE_SCALE 0.f
#else
	#define EDGE_SCALE .0100f
#endif

#define EDGE_THICK .33f

#define GRID_SCALE .0075f
#define      SCALE .02f
#define MAX_CIRCLE_ASP 1.55f
#define COLL_BUF 2.f

static enum mode {
	  MODE_NAV
	, MODE_EDIT
} mode;

typedef struct {
	uid uid;
	istr body;
	int x, y;
	int size;
	int sty;
	int col;
	ff seed;

	int seeded;
	uid parent;
	ff ext;
	int dirty;
} node;

VBUF(nodes, node, 1024);
static node *sel;

static node *find_node(const uid uid)
{
	VBUF_FOREACH(nodes, node) {
		if (node->uid != uid)
			continue;
		return node;
	}

	panic();
}

static ff node_pos(const node *node)
{
	return $ * [ node->x' node->y' ] GRID_SCALE
}

static void node_set_ext(node *node)
{
	float width = 0.f;
	float swap = 0.f;

	float height = 1.f;

	for (char *c = (char*)node->body; *c; ++c) {
		if (*c == '\n') {
			width = maxf(swap, width);
			swap = 0.f;
			++height;
			continue;
		}

		++swap;
	}

	width = maxf(swap, width);
	swap = 0.f;

	node->ext = (ff) {
		.x = width,
		.y = height,
	};
}

static ff node_ext(const node *node)
{
	ff result = {
		.x = maxf(6.f, node->ext.x + 4.f),
		.y = maxf(6.f, node->ext.y + 4.f),
	};

	const float grow = 1 + node->size * .25f;
	return $ * result'2 * SCALE' grow

}

static float node_r(const node *node)
{
	const ff r = node_ext(node);
	return maxf(r.x, r.y) * .5f;
}

static void node_seed(node *node)
{
	assert(!node->seeded);

	size_t seed;
	size_t len = strlen(node->body);
	{
		seed = 5381;
		for (u32 i = 0; i < len; ++i) {
			char c = node->body[i];
			if (isalpha(c) || isdigit(c))
				seed += (seed << 5) + c;
		}
	}

	srand(seed);
	node->seed = (ff) { srandf(), srandf() };
	node->seeded = 1;
}

typedef struct {
	uid a, b;
	int sty;
} edge;

VBUF(edges, edge, 1024);

static char edit_buf[512];
static u32  edit_n;
void inp_ev_text(unsigned int unicode)
{
	if (mode != MODE_EDIT)
		return;

	char ascii = unicode;
	edit_buf[edit_n++] = ascii;

	assert(sel);
	sel->dirty = 1;
}

static void edit_update()
{
	assert(mode == MODE_EDIT);

	if (edit_n) {
		static float rep;
		rep += _time.dt.real;

		if (KEY_DOWN(BACKSPACE)) {
			edit_buf[--edit_n] = 0;
			rep = -DEL_DEL_S;
		}

		else if (KEY_HELD(BACKSPACE)) {
			if (rep > DEL_REP_S) {
				edit_buf[--edit_n] = 0;
				rep = 0.f;
			}
		}
	}

	if (KEY_DOWN(ENTER)) {
		edit_buf[edit_n++] = '\n';
	}
}

static void edit_clear()
{
	memset(edit_buf, 0, 512);
	edit_n = 0;
}

static int is_err;
static char err_msg[256];
static void err(char *restrict format, ...)
{
	va_list ap;
	va_start(ap, format);

	vsnprintf(err_msg, 256, format, ap);

	VBUF_CLEAR(nodes);
	VBUF_CLEAR(edges);

	is_err = 1;
}

typedef struct txt_buf* txt;
static txt dbg_txt;
static u32 dbg_n;

static void debug_str(char *restrict format, ...)
{
	if (!dbg_txt)
		return;

	va_list ap;
	va_start(ap, format);

	static char swap[512];
	vsnprintf(swap, 512, format, ap);

	const ff pos = $ 0 * dbg_n++' -.02

	struct block_ctx ctx = block_prepare(
		(struct block) {
			.str = swap,
			.scale = .01f,
			.pos = @ pos.x' pos.y' 0
			.rot = @ id
			.anch = @ zero'2
			.justify = JUST_CENTER,
			.spacing = 1.f,
			.line_height = 1.f,
		}
	);

	struct sprite sprite;
	while (block_draw(&sprite, &ctx, dbg_txt)) {
		sprite.asc ^= islower(sprite.asc) ? ' ' : 0;
		sprite.col = COL_TEXT;
		sprite_draw_imm(sprite, dbg_txt);
	}
}

struct man {
	ff pos;
	int rect;
	union {
		ff ext;
		float r;
	};
};

static struct man manifold(node *node)
{
	const ff pos = node_pos(node);
	struct man result = { .pos = pos };

	const ff ext = node_ext(node);
	const float asp = ext.x / ext.y;

	if (asp < MAX_CIRCLE_ASP && asp > 1.f / MAX_CIRCLE_ASP) {
		result.r = node_r(node);
	} else {
		result.rect = 1;
		result.ext = ext;
	}

	return result;
}

static int rect_rect(struct man a, struct man b)
{
	assert(a.rect);
	assert(b.rect);

	const float buf = GRID_SCALE * COLL_BUF;

	/* Four bounding lines */

	const float al = a.pos.x - (a.ext.x + buf) * .5f;
	const float ar = a.pos.x + (a.ext.x + buf) * .5f;
	const float ad = a.pos.y - (a.ext.y + buf) * .5f;
	const float au = a.pos.y + (a.ext.y + buf) * .5f;

	const float bl = b.pos.x - (b.ext.x + buf) * .5f;
	const float br = b.pos.x + (b.ext.x + buf) * .5f;
	const float bd = b.pos.y - (b.ext.y + buf) * .5f;
	const float bu = b.pos.y + (b.ext.y + buf) * .5f;

	return al < br && ar > bl && au > bd && ad < bu;
}

static int circle_circle(struct man a, struct man b)
{
	assert(!a.rect);
	assert(!b.rect);

	const float buf = GRID_SCALE * COLL_BUF;

	float dist = $ len - a.pos'2 b.pos
	return dist < a.r + b.r + buf;
}

static int rect_circle(struct man a, struct man b)
{
	assert( a.rect);
	assert(!b.rect);

	const float buf = GRID_SCALE * COLL_BUF;

	const float al = a.pos.x - (a.ext.x + buf) * .5f;
	const float ar = a.pos.x + (a.ext.x + buf) * .5f;
	const float ad = a.pos.y - (a.ext.y + buf) * .5f;
	const float au = a.pos.y + (a.ext.y + buf) * .5f;

	// A 'conservative' check
	const float bl = b.pos.x - (b.r + buf);
	const float br = b.pos.x + (b.r + buf);
	const float bd = b.pos.y - (b.r + buf);
	const float bu = b.pos.y + (b.r + buf);

	return al < br && ar > bl && au > bd && ad < bu;
}

static int collides_prev(node *cmp)
{
	struct man man_cmp = manifold(cmp);

	VBUF_FOREACH(nodes, node) {
		if (cmp == node)
			break;

		struct man man = manifold(node);

		if (man.rect && man_cmp.rect) {
			if (rect_rect(man, man_cmp))
				return 1;
		}

		else if (!man.rect && !man_cmp.rect) {
			if (circle_circle(man, man_cmp))
				return 1;
		}

		else if (man.rect) {
			assert(!man_cmp.rect);
			if (rect_circle(man, man_cmp))
				return 1;
		}

		else {
			assert(man_cmp.rect);
			assert(!man.rect);
			if (rect_circle(man_cmp, man))
				return 1;
		}
	}

	return 0;
}

static int find_pos(node *child)
{
	const float range = 32.f;
	ff dir;

	if (child->parent) {
		node *parent = find_node(child->parent);
		child->x = parent->x;
		child->y = parent->y;
		dir = $ norm child->seed'2
	} else {
		child->x = child->seed.x * range;
		child->y = child->seed.y * range;
		dir = $ * norm - node_pos(child)'2 zero 2
	}

	// 'Invalidate' future nodes only
	int result = 0;
	while (collides_prev(child)) {
		int x = roundf(dir.x * 2.f);
		int y = roundf(dir.y * 2.f);
		assert(x | y);
		child->x += x;
		child->y += y;
		result = 1;
	}

	return result;
}

static void init()
{
	cam.scale = 1.f;
	cam.rot = 0.f;
}

static float sel_timer = 6.f;
static void update()
{
	struct {
		int graph;
		int cam;
	} dirty = { };

	sel_timer = minf(sel_timer + _time.dt.real, 8.f);

	static float asp_prev;
	if (asp_prev != cam.asp)
		dirty.cam = 1;
	asp_prev = cam.asp;

	const int ctrl_c = KEY_HELD(LEFT_CONTROL)
		&& KEY_DOWN(C);
	const int esc = KEY_DOWN(ESCAPE);
	const int kill = ctrl_c | esc;

	switch (mode) {
		case MODE_NAV: {
			if (kill)
				exit(0);

			if (KEY_DOWN(ENTER)) {
				mode = MODE_EDIT;
				sel = VBUF_PUSH(nodes);

				*sel = (node) {
					.uid = uids++,
					.body = edit_buf,
					.dirty = 1,
				};

				node_seed(sel);
				find_pos(sel);
				dirty.cam = 1;
			}

			if (KEY_DOWN(TAB)) {
				int i = sel - nodes;
				if (KEY_HELD(LEFT_SHIFT))
					--i;
				else
					++i;
				sel = nodes + (i % nodes_n);
				sel_timer = 0.f;
			}

			break;
		}
		case MODE_EDIT: {
			edit_update();

			if (kill) {
				sel->body = intern(edit_buf, edit_n);
				edit_clear();
				mode = MODE_NAV;
				sel_timer = 0.f;
			}
		}
	}

	VBUF_FOREACH(nodes, node) {
		if (!node->dirty)
			continue;

		node_set_ext(node);
		dirty.graph |= find_pos(node);
		dirty.cam = 1;
		node->dirty = 0;
	}

	if (dirty.graph) {
		VBUF_FOREACH(nodes, node) {
			find_pos(node);
		}
	}

	if (dirty.cam) {
		ff ext_x = { __FLT_MAX__, -__FLT_MAX__ };
		ff ext_y = { __FLT_MAX__, -__FLT_MAX__ };

		VBUF_FOREACH(nodes, node) {
			const ff pos = node_pos(node);
			const ff ext = node_ext(node);

			ext_x.x = minf(ext_x.x, pos.x - ext.x * .5f);
			ext_x.y = maxf(ext_x.y, pos.x + ext.x * .5f);

			ext_y.x = minf(ext_y.x, pos.y - ext.y * .5f);
			ext_y.y = maxf(ext_y.y, pos.y + ext.y * .5f);
		}

		cam.pos = (ff) {
			@ mix' ext_x.x ext_x.y .5
			@ mix' ext_y.x ext_y.y .5
		};

		const float scale = maxf(
			(ext_x.y - ext_x.x) / cam.asp,
			 ext_y.y - ext_y.x
		);

		const float buf = 8.f * GRID_SCALE;
		cam.scale = scale + buf;
	}
}

static void update_fixed()
{
}

static void sprite_draw_edge(struct sprite sprite, struct txt_buf *txt)
{
	const float thick = clamp01f(EDGE_THICK);

	struct txt_quad quad = sprite_conv(sprite);
	quad.model = m4_model_aniso(
		@ + sprite.pos app sprite.rot * [ -.5 + -.5 thick 0 ] sprite.scale
		sprite.rot,
		(v3) { sprite.scale, sprite.scale * thick, 1.f }
	);
	quad_draw_imm(quad, txt);
}

static void render(txt txt)
{
	dbg_txt = txt;
	dbg_n = 0;

	if (is_err) {
		struct block_ctx ctx = block_prepare(
			(struct block) {
				.str = err_msg,
				.scale = SCALE * .75f,
				.pos = @ zero'3
				.rot = @ id
				.anch = @ zero'2
				.justify = JUST_CENTER,
				.spacing = 1.f,
				.line_height = 1.f,
			}
		);

		struct sprite sprite;
		while (block_draw(&sprite, &ctx, dbg_txt)) {
			sprite.asc ^= islower(sprite.asc) ? ' ' : 0;
			sprite.col = COL_ERR;
			sprite_draw_imm(sprite, dbg_txt);
		}

		cam.pos = $ zero'2
		cam.scale = 1.f;
		return;
	}

	VBUF_FOREACH(nodes, node) {
		const ff root = node_pos(node);
		const float angle = node->seed.x * node->seed.y;

		const float grow = 1 + node->size * .25f;
		float scale = SCALE * grow;

		struct block_ctx ctx = block_prepare(
			(struct block) {
				.str = *node->body ? node->body : "...",
				.scale = scale,
				.pos = @ root.x' root.y' 0
				.rot = @ axis-angle fwd * angle' .05
				.anch = @ 0 0
				.justify = JUST_CENTER,
				.spacing = 1.f,
				.line_height = 1.f,
			}
		);

		v3 col_fg, col_bg;
		if (node->body == edit_buf)
			col_fg = col_bg = COL_EDIT;
		else if (node == sel && sel_timer < 3.f) {
			const float x = $ ^ / sel_timer' 3 2
			col_fg = $ mix'3 COL_SEL COL_TEXT x
			col_bg = $ mix'3 COL_SEL COL_EDGE x
		} else {
			col_fg = COL_TEXT;
			col_bg = COL_EDGE;
		}

		if (node->sty < 0) {
			col_fg = $ mix'3 COL_TABLE col_fg ^ .75 -node->sty
			col_bg = $ mix'3 COL_TABLE col_bg ^ .75 -node->sty
		}

		struct sprite sprite;
		while (block_draw(&sprite, &ctx, dbg_txt)) {
			const float alpha = minf(1.f, _time.el.real * 16.f);
			const int hi = MAX(0, MIN(1, node->sty));

			sprite.col = col_fg;
			sprite.asc ^= islower(sprite.asc) ? ' ' : 0;
			sprite.vfx = (v3) { alpha, hi, 0 };
			sprite_draw_imm(sprite, txt);
		}

		const ff ext = node_ext(node);
		const float asp = ext.x / ext.y;

		scale = SCALE * .6f;
		const float density = .3f;

		if (asp < MAX_CIRCLE_ASP && asp > 1.f / MAX_CIRCLE_ASP) {
			const float r = node_r(node);
			const float c = 2.f * M_PI * r;
			const u16 n = (int)EDGE_SCALE ?
				MAX(8, c * density / EDGE_SCALE) :
				c / scale + 3;

			for (u16 i = 0; i < n; ++i) {
				const float a = 2.f * M_PI * i / (float)n;
				const ff pos = $ + root * [ sin a cos a ] r

				sprite = (struct sprite) {
					.pos = @ pos.x' pos.y' 0
					.col = col_bg,
					.rot = @ axis-angle back a
					.scale = scale,
					.anch = @ 0 0
					.vfx = @ 1 0 0
					.asc = 1,
					.bounds = V4_ZERO,
				};

				sprite_draw_edge(sprite, txt);
			}
		} else {
			const ff ext = node_ext(node);
			float c;
			u16 n;

			c = ext.x;
			n = (int)EDGE_SCALE ?
				MAX(1, c * density / EDGE_SCALE) :
				c / scale + 3;
			for (u16 i = 0; i < n; ++i) {
				ff pos;

				pos.x = root.x + -ext.x * .5f;
				pos.y = root.y +  ext.y * .5f;
				pos.x += ext.x * (float)i / (n - 1);

				sprite = (struct sprite) {
					.pos = @ pos.x' pos.y' 0
					.col = col_bg,
					.rot = @ id
					.scale = scale,
					.anch = @ 0 0
					.vfx = @ 1 0 0
					.asc = 1,
					.bounds = V4_ZERO,
				};

				sprite_draw_edge(sprite, txt);

				pos.x = root.x + -ext.x * .5f;
				pos.y = root.y -  ext.y * .5f;
				pos.x += ext.x * (float)i / (n - 1);

				sprite = (struct sprite) {
					.pos = @ pos.x' pos.y' 0
					.col = col_bg,
					.rot = @ id
					.scale = scale,
					.anch = @ 0 0
					.vfx = @ 1 0 0
					.asc = 1,
					.bounds = V4_ZERO,
				};

				sprite_draw_edge(sprite, txt);
			}

			c = ext.y;
			n = (int)EDGE_SCALE ?
				MAX(2, c * density / EDGE_SCALE) :
				c / scale + 3;
			for (u16 i = 0; i < n; ++i) {
				ff pos;

				pos.x = root.x - ext.x * .5f;
				pos.y = root.y - ext.y * .5f;
				pos.y += ext.y * (float)i / (n - 1);

				sprite = (struct sprite) {
					.pos = @ pos.x' pos.y' 0
					.col = col_bg,
					.rot = @ axis-angle fwd * pi .5
					.scale = scale,
					.anch = @ 0 0
					.vfx = @ 1 0 0
					.asc = 1,
					.bounds = V4_ZERO,
				};

				sprite_draw_edge(sprite, txt);

				pos.x = root.x + ext.x * .5f;
				pos.y = root.y - ext.y * .5f;
				pos.y += ext.y * (float)i / (n- 1);

				sprite = (struct sprite) {
					.pos = @ pos.x' pos.y' 0
					.col = col_bg,
					.rot = @ axis-angle fwd * pi .5
					.scale = scale,
					.anch = @ 0 0
					.vfx = @ 1 0 0
					.asc = 1,
					.bounds = V4_ZERO,
				};

				sprite_draw_edge(sprite, txt);
			}
		}
	}

	if (KEY_HELD(SPACE) && mode != MODE_EDIT)
		return;

	VBUF_FOREACH(edges, edge) {
		assert(edge->a != edge->b);
		const node *a = find_node(edge->a);
		const node *b = find_node(edge->b);

		const ff a_pos = node_pos(a);
		const ff b_pos = node_pos(b);

		const ff diff = $ - b_pos'2 a_pos
		const ff dir = $ norm diff'2
		const float dist = $ len diff'2

		const float scale = SCALE * .25f;

		u16 n = (int)EDGE_SCALE ?
			.5f * dist / EDGE_SCALE :
			dist / scale + 3; // 1 to round, two for the caps
		const v3 col = $ mix'3 COL_TEXT COL_TABLE .8

		for (u16 i = 0 + 1; i < n - 1; ++i) {
			const float x = (float)i / (n - 1);
			const ff pos = $ mix'2 a_pos b_pos x

			v3 dir3 = { .xy = dir };

			struct sprite sprite;
			sprite = (struct sprite) {
				.pos = @ pos.x' pos.y' .5
				.col = col,
				.rot = @ qt/fwd fwd cross fwd dir3
				.scale = scale,
				.anch = @ 0 0
				.vfx = @ 1 0 0
				.asc = 1,
				.bounds = V4_ONE,
			};

			sprite_draw_imm(sprite, txt);
		}
	}
}

static int is_punct_size(const char c)
{
	switch (c) {
	case '+':
	case '-':
		return 1;
	default:
		return 0;
	}
}

static int is_punct_sty(const char c)
{
	switch (c) {
	case '*':
	case '>':
		return 1;
	default:
		return 0;
	}
}

static int is_punct(const char c)
{
	return is_punct_size(c) | is_punct_sty(c);
}

static void load(const char *path, const int throw)
{
	uids = 0;
	is_err = 0;

	FILE *file = fopen(path, "r");
	if (!file) {
		if (throw)
			panic_perr(path);
		return err("missing '%s'", path);
	}

	int hash = 0; // Zero is fine, but we could hash via the filename

	VBUF_CLEAR(nodes);
	VBUF_CLEAR(edges);

	size_t len = 0;
	ssize_t n;
	char *line = NULL;

	VBUF_MK(chain, node*, 16);
	VBUF_PUSH(chain);
	u32 indent = 0;

	*chain = NULL;

	size_t n_line = 0;
	while (-1 != (n = getline(&line, &len, file))) {
		++n_line;

		if (*line == '\n')
			continue;

		if (!strncmp(line, "###", 3))
			break;
		if (*line == '#')
			continue;

		u32 k = 0;
		char *c = line;
		while (*c++ == '\t')
			++k;
		--c;

		if (!strncmp(c, "###", 3))
			break;
		if (*c == '#')
			continue;

		if (k > indent) {
			if (k - indent != 1 || !*chain) {
				return err(
					"<%s:%lu:%u> bad indent!",
					path,
					n_line, 1 + c - line
				);
			}

			++indent;
			VBUF_PUSH(chain);
		} else {
			while (k < indent) {
				VBUF_POP(chain);
				--indent;
			}
		}

		int size = 0, sty = 0;
		while (is_punct(*c) || isspace(*c)) {
			if (*c == '\n')
				break;

			switch (*c) {
			case '+':
				++size;
				break;
			case '-':
				--size;
				break;
			case '*':
				++sty;
				break;
			case '>':
				--sty;
				break;
			default:
				break;
			}

			++c;
		}

		char *prev = NULL;
		for (char *trail = c; *trail != '\n'; ++trail) {
			if ('\\' == *trail)
				*trail = '\n';

			if (!(is_punct(*trail) | isspace(*trail)))
				prev = NULL;
			else if (!prev)
				prev = trail;
		}

		if (!size && !sty) // Ignore postfix if no prefix exists
			prev = NULL;

		u32 len = (n - 1) // Remove newline
			- (c - line);
		if (prev)
			len -= (len - (prev - c));

		if (!len) // Empty
			continue;

		sel = VBUF_PUSH(nodes);
		chain[chain_n - 1] = sel;

		*sel = (node) {
			.uid = uids++,
			.body = intern(c, len),
			.size = size,
			.sty = sty,
			.dirty = 1,
		};

		node *parent = chain_n > 1 ? chain[chain_n - 2] : NULL;
		if (parent) {
			sel->parent = parent->uid;

			*VBUF_PUSH(edges) = (edge) {
				.a = parent->uid,
				.b = sel->uid,
			};
		}

		node_set_ext(sel);
	}

	if (line)
		free(line);
	fclose(file);

	srand(hash);
	VBUF_FOREACH(nodes, node) {
		node_seed(node);
		find_pos(node);
	}
}
