#version 450

#include "txtquad/config.h"
#define PIX_WIDTH_ST (1.f / CHAR_WIDTH)

#define GL
#include "share.h"

layout (location = 0) in  vec2 uv;
layout (location = 1) in  vec2 st;
layout (location = 2) in  vec4 col;
layout (location = 3) in  vec2 fx;
layout (location = 0) out vec4 final;

layout (set = 1, binding = 0) uniform Share {
	mat4 vp;
} share;

layout (set = 0, binding = 0) uniform texture2D img;
layout (set = 0, binding = 1) uniform sampler unf;

void main()
{
	const float alpha = (1.f - col.a) * (1.f - col.a);
	if (alpha > (1.f + 2.f * (BIAS + PADDING)) - abs((st.y - .5f) * 2.f))
		discard; // Fade

	float b = texture(sampler2D(img, unf), uv).r;
	vec3 rgb = col.rgb;

	if (min(st.x, st.y) < 0 || max(st.x, st.y) > 1 || b == 0) {
		if (fx.x == 0) discard;

		// Clear bonus pixel (font only)
		if (st.x > 1.f) discard;

		float top = mix(.5f, (1.f + PIX_WIDTH_ST), fx.x);
		float bot = mix(.5f, (0.f - PIX_WIDTH_ST), fx.x);
		if (st.y > top) discard;
		if (st.y < bot) discard;

		rgb = mix(COL_HIL, COL_TABLE, .3f);
	}

	else rgb *= b;
	final = vec4(rgb, 1);
}
