shader_type canvas_item;
render_mode blend_mix, unshaded;

// 棋盘外发光只用 SDF 把一维贴图轮廓绕到圆角矩形边缘。
// 发光的明暗/渐变全部来自 glow_profile，不在 Shader 内生成模糊或渐变。
uniform sampler2D glow_profile : source_color, hint_default_transparent, filter_linear, repeat_disable;
uniform vec2 panel_size_px = vec2(1136.0);
uniform vec2 board_size_px = vec2(1008.0);
uniform float corner_radius_px : hint_range(0.0, 128.0, 1.0) = 30.0;
uniform float profile_span_px : hint_range(1.0, 256.0, 1.0) = 64.0;

float rounded_rect_distance(vec2 point, vec2 half_size, float radius) {
	float safe_radius = clamp(radius, 0.0, min(half_size.x, half_size.y));
	vec2 offset = abs(point) - (half_size - vec2(safe_radius));
	return length(max(offset, vec2(0.0))) + min(max(offset.x, offset.y), 0.0) - safe_radius;
}

void fragment() {
	vec4 canvas_color = COLOR;
	vec2 pixel = UV * panel_size_px;
	vec2 centered = pixel - panel_size_px * 0.5;
	float distance_to_board = rounded_rect_distance(centered, board_size_px * 0.5, corner_radius_px);

	// 贴图底边固定贴住白底真实轮廓，向外按整张贴图展开。
	float profile_v = 1.0 - distance_to_board / max(profile_span_px, 0.0001);
	if (profile_v >= 0.0 && profile_v <= 1.0) {
		vec4 profile_color = texture(glow_profile, vec2(0.5, profile_v));
		COLOR = canvas_color * profile_color;
	} else {
		COLOR = vec4(0.0);
	}
}
