shader_type canvas_item;

/// 2D 流动条 + 蒙版 + 预乘 + 可选 Add 读屏加算
/// 凡「可视为 0 透明度/0 加算」的片元 discard，避免挡下层

render_mode blend_premul_alpha;

// 内置下限：检查器全 0 时仍可靠去掉「几乎为 0」的片元（可按工程改）
const float KILL_A = 0.00025;
const float KILL_ADD = 0.0002;
const float EPS = 0.0001;

uniform vec2 scroll_speed = vec2(0.0, 0.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float base_rotation = 0.0;
uniform vec2 base_uv_offset = vec2(0.0, 0.0);
uniform bool base_repeat = true;

uniform sampler2D mask_texture : hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform float mask_rotation = 0.0;
uniform vec2 mask_scale = vec2(1.0, 1.0);
uniform vec2 mask_offset = vec2(0.0, 0.0);
uniform vec2 mask_uv_offset = vec2(0.0, 0.0);
uniform bool mask_repeat = true;
uniform float mask_strength : hint_range(0.0, 1.0) = 1.0;
uniform float mask_invert : hint_range(0.0, 1.0) = 0.0;
/// true: m = A*max(R,G,B)；false: m = 仅 A
uniform bool mask_luminance = true;

uniform bool add_mode = false;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

/// Alpha 切除
uniform float alpha_cut : hint_range(0.0, 0.1) = 0.0;
/// 主色/蒙版上「当黑用」
uniform float black_transparent_threshold : hint_range(0.0, 0.2) = 0.0;
/// 与内置 KILL 叠加，收紧软边/灰边
uniform float invisible_epsilon : hint_range(0.0, 0.02) = 0.0;

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

vec2 rotate_at_center(vec2 uv, float degrees_ccw) {
	float rad = radians(degrees_ccw);
	float c = cos(rad);
	float s = sin(rad);
	vec2 p = uv - vec2(0.5);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c) + vec2(0.5);
}

vec2 wrap_uv(vec2 uv, bool do_repeat) {
	if (do_repeat) {
		return fract(uv);
	}
	return clamp(uv, vec2(0.0), vec2(1.0));
}

void fragment() {
	vec2 b_uv = wrap_uv(
		rotate_at_center(UV, base_rotation) * uv_scale + scroll_speed * TIME + base_uv_offset,
		base_repeat
	);
	vec4 ta = texture(TEXTURE, b_uv);

	vec2 m_uv = wrap_uv(
		rotate_at_center(UV, mask_rotation) * uv_scale * mask_scale + mask_offset + mask_uv_offset,
		mask_repeat
	);
	vec4 ms = texture(mask_texture, m_uv);

	float mk = max(max(ms.r, ms.g), ms.b);
	float m0 = mask_luminance ? (ms.a * mk) : ms.a;
	m0 = clamp(m0 * mask_strength, 0.0, 1.0);
	if (m0 <= (black_transparent_threshold + EPS)) {
		m0 = 0.0;
	}
	m0 = mix(m0, 1.0 - m0, mask_invert);
	float m = min(m0, ta.a);

	float shape = clamp(ta.a - m, 0.0, 1.0);
	vec3 rgb = ta.rgb * item_modulate.rgb;
	float a = shape * item_modulate.a;

	// ① 全透明/浮点毛刺
	if (a < KILL_A) {
		discard;
	}
	float a_need = max(alpha_cut, 0.0) + max(invisible_epsilon, 0.0) + KILL_A;
	if (a < a_need) {
		discard;
	}
	// ② 主色近黑/纯黑
	float luma = max(max(rgb.r, rgb.g), rgb.b);
	if (luma <= max(black_transparent_threshold, 0.0) + 0.001) {
		discard;
	}

	if (add_mode) {
		vec3 energy = rgb * a;
		if (max(max(energy.r, energy.g), energy.b) < (KILL_ADD + max(invisible_epsilon, 0.0))) {
			discard;
		}
		vec3 b = texture(screen_texture, SCREEN_UV).rgb;
		COLOR = vec4(clamp(b + energy, vec3(0.0), vec3(1.0)), 1.0);
	} else {
		COLOR = vec4(rgb * a, a);
	}
}