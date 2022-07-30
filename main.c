#include <stdlib.h>
#include <assert.h>
#include <time.h>

#include "txtquad/txtquad.h"
#include "txtquad/inp.h"

#include "acg/sys.h"
#include "acg/ds.h"

#define FIXED_DT (1.f / 120.f)
#include "acg/time.h"
struct _time _time;

#include "acg/cam.h"
cam2 cam;

#include "share.h"
#include "impl.h"

static const char *path;

#ifdef WATCH
#include <sys/stat.h>
static time_t t_prev;

static int src_dirty()
{
	struct stat out;
	const int err = stat(path, &out);

	if (err)
		return 0; // This may occur 'spuriously'

	const int result = out.st_mtime > t_prev;
	t_prev = out.st_mtime;
	return result;
}
#endif

struct txt_share txtquad_update(struct txt_frame frame, struct txt_buf *txt)
{
#ifdef WATCH
	if (src_dirty())
		load(path, 0);
#endif
	txt->count = 0;
	cam.asp = (float)frame.size.w / frame.size.h;
	_time.scale = 1.f;

	if (_time_tick(&frame.t, &frame.dt)) {
		/* ... */
	}

	while (_time_step()) {
		update_fixed();
	}

	update();
	render(txt);

	return (struct txt_share) {
		.vp = cam2_conv(cam),
	};
}

int main(int argc, char **argv)
{
	init_interns();

	path = *(argv + 1) ?: "map";
	load(path, 1);

	dump_vmem();

	int key_handles[] = {
		  KEY(SPACE)
		, KEY(LEFT_SHIFT)
		, KEY(LEFT_CONTROL)
		, KEY(TAB)
		, KEY(ENTER)
		, KEY(BACKSPACE)
		, KEY(ESCAPE)
		, KEY(GRAVE_ACCENT)
		, KEY(LEFT)
		, KEY(RIGHT)
		, KEY(UP)
		, KEY(DOWN)
		, KEY(H)
		, KEY(J)
		, KEY(K)
		, KEY(L)
		, KEY(W)
		, KEY(A)
		, KEY(S)
		, KEY(D)
		, KEY(R)
		, KEY(Q)
		, KEY(E)
		, KEY(C)
		, KEY(X)
		, KEY(Z)
	};

	int btn_handles[] = {
		  BTN(1)
		, BTN(2)
	};

	inp_key_init(key_handles, sizeof(key_handles) / sizeof(int));
	inp_btn_init(btn_handles, sizeof(btn_handles) / sizeof(int));

	txtquad_init((struct txt_cfg) {
		.app_name = "map",
		.asset_path = "./assets/",
		.mode = MODE_WINDOWED,
		.win_size = { 1024, 1024 },
		.resizable = 1,
		.clear_col = COL_TABLE,
	});

	init();
	txtquad_start();
}
