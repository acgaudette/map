#version 450

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
	if (min(st.x, st.y) < 0 || max(st.x, st.y) > 1)
		discard; // Padding

	float b = texture(sampler2D(img, unf), uv).r;
	if (0 == b)
		discard; // Alpha

	vec3 rgb = col.rgb;

	if ((1.f - col.a) * (1.f - col.a) > 1.f - abs((st.y - .5f) * 2.f))
		discard; // Fade

	final = vec4(rgb, 1);
}
