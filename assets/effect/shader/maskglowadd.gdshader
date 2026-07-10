shader_type canvas_item;
render_mode blend_add;

uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);

uniform float angle_deg : hint_range(-180.0, 180.0) = 0.0;
uniform float band : hint_range(0.01, 0.6) = 0.12;
uniform float softness : hint_range(0.001, 0.5) = 0.08;
uniform float intensity : hint_range(0.0, 5.0) = 1.0;
uniform float add_strength : hint_range(0.0, 3.0) = 0.35;
uniform float progress : hint_range(-1.0, 2.0) = -1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// 只在原图不透明区域扫（避免扫到透明区域）
	float shape_mask = tex.a;

	float rad = radians(angle_deg);
	vec2 dir = vec2(cos(rad), sin(rad));

	float proj = dot(UV - vec2(0.5), dir) + 0.5;
	float dist = abs(proj - progress);

	float k = 1.0 - smoothstep(band, band + softness, dist);
	float shine_mask = clamp(k * intensity, 0.0, 1.0) * shape_mask;

	vec3 rgb = shine_color.rgb * add_strength;
	float a = shine_mask * shine_color.a;

	// 关键：没有扫光的地方必须完全不加（a=0），才不会形成“挡板”
	COLOR = vec4(rgb, a);
}