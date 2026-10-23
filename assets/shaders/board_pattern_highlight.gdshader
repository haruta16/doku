shader_type canvas_item;
render_mode unshaded;

uniform sampler2D cell_mask : filter_linear, repeat_disable;
uniform vec2 rect_size_px = vec2(1.0);
uniform float sweep_progress : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float sweep_alpha : hint_range(0.0, 1.0, 0.001) = 0.35;
uniform float sweep_half_width_px = 180.0;
uniform float sweep_softness_px = 20.0;

vec2 safe_uv(vec2 uv) {
	return clamp(uv, vec2(0.0), vec2(1.0));
}

void fragment() {
	// 屏幕坐标 y 轴向下，(1,-1) 即左下 → 右上的 45° 运动方向。
	vec2 direction = normalize(vec2(1.0, -1.0));
	vec2 centered_px = UV * rect_size_px - rect_size_px * 0.5;
	float axis = dot(centered_px, direction);
	float extent = dot(rect_size_px * 0.5, abs(direction));
	float travel = extent + sweep_half_width_px;
	float sweep_center = mix(-travel, travel, sweep_progress);
	float dist = abs(axis - sweep_center);
	float edge0 = max(0.0, sweep_half_width_px - sweep_softness_px);
	float band = 1.0 - smoothstep(edge0, sweep_half_width_px, dist);
	float sweep_a = texture(cell_mask, safe_uv(UV)).r * band * sweep_alpha;
	COLOR = vec4(1.0, 1.0, 1.0, sweep_a);
}
