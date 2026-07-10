shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);

uniform float angle_deg : hint_range(-180.0, 180.0) = 0.0;

uniform float band : hint_range(0.01, 0.6) = 0.12;
uniform float softness : hint_range(0.001, 0.5) = 0.08;
uniform float intensity : hint_range(0.0, 5.0) = 1.0;

uniform float add_strength : hint_range(0.0, 3.0) = 0.35;

uniform float progress : hint_range(-1.0, 2.0) = -1.0;

// 0 = Mix（替换式扫光）；1 = Add（底色 + 扫光，偏 AE/Unity 相加感）
uniform int blend_mode : hint_range(0, 1) = 1;

// 是否用 base_color.a 参与“有效像素”裁剪（一般建议开）
uniform bool mask_use_base_alpha = true;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	vec3 c = tex.rgb * base_color.rgb;
	float a = tex.a * base_color.a;

	// 原图有效像素遮罩：扫光只作用在 sprite 不透明区域
	float shape_mask = tex.a;
	if (mask_use_base_alpha) {
		shape_mask *= base_color.a;
	}

	float rad = radians(angle_deg);
	vec2 dir = vec2(cos(rad), sin(rad));

	float proj = dot(UV - vec2(0.5), dir) + 0.5;
	float dist = abs(proj - progress);

	float k = 1.0 - smoothstep(band, band + softness, dist);
	float shine_mask = clamp(k * intensity, 0.0, 1.0);

	// 关键：扫光识别原图 alpha（避免在透明区域出现斜条脏边）
	shine_mask *= shape_mask;

	vec3 shine_contrib = shine_color.rgb * shine_mask * add_strength * shine_color.a;

	vec3 rgb;
	float out_a;

	if (blend_mode == 0) {
		rgb = mix(c, shine_color.rgb, shine_mask);
		float shine_a = shine_color.a * shine_mask;
		out_a = max(a, shine_a);
	} else {
		vec3 base_rgb = c * a;
		rgb = base_rgb + shine_contrib;

		float shine_a = shine_color.a * shine_mask;
		out_a = max(a, shine_a);

		rgb = clamp(rgb, vec3(0.0), vec3(1.0));
	}

	COLOR = vec4(rgb, out_a);
}