shader_type canvas_item;
render_mode blend_mix;

uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float angle_deg : hint_range(-180.0, 180.0) = 0.0;
uniform float band : hint_range(0.01, 0.6) = 0.12;
uniform float softness : hint_range(0.001, 0.5) = 0.08;
uniform float intensity : hint_range(0.0, 5.0) = 1.0;

// 只影响“多亮/多宽”，不改变色相：乘到 alpha（不乘 rgb）
uniform float add_strength : hint_range(0.0, 3.0) = 1.0;

uniform float progress : hint_range(-1.0, 2.0) = -1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	float shape_mask = tex.a;

	float rad = radians(angle_deg);
	vec2 dir = vec2(cos(rad), sin(rad));

	float proj = dot(UV - vec2(0.5), dir) + 0.5;
	float dist = abs(proj - progress);

	float k = 1.0 - smoothstep(band, band + softness, dist);
	float shine_mask = clamp(k * intensity, 0.0, 1.0) * shape_mask;

	// 关键：rgb 直接用 shine_color（不要再乘 add_strength）
	vec3 rgb = shine_color.rgb;

	// 强度只进 alpha：扫光条颜色与 Shine Color 一致，整体明暗用 add_strength 调
	float a = shine_mask * shine_color.a * add_strength;

	COLOR = vec4(rgb, clamp(a, 0.0, 1.0));
}