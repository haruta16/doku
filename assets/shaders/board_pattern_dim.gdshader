shader_type canvas_item;
render_mode unshaded;

// 黑色压暗遮罩，铺在 BoardView 区域（不是全屏，见 board_pattern_sweep_overlay._apply_geometry）。
// 实际不透明度由 dim_alpha 逐帧驱动（三段淡入/保持/淡出），峰值见 _DIM_MAX_ALPHA。
// mask_rect 是特殊格局部纹理在**本层自身 UV**（= BoardView 矩形）中的归一化矩形；
// mask_texture 白色区域对应特殊格，那里挖空保持原亮度。
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float dim_alpha : hint_range(0.0, 1.0, 0.001) = 0.0;
// 本层自身的屏幕像素尺寸 + 圆角半径，用于把压暗区裁成与棋盘白底一致的圆角矩形。
// 不裁的话四角会露出直角暗块（棋盘白底是圆角的）。半径取 BoardView.BOARD_BG_CORNER_RADIUS，
// 该常量经 BoardView._draw 的 scale 反向补偿后渲染值恒为屏幕像素，故此处直接当屏幕像素用。
uniform vec2 rect_size_px = vec2(1.0);
uniform float corner_radius_px = 0.0;

void fragment() {
	vec2 rect_size = max(mask_rect.zw, vec2(0.000001));
	vec2 mask_uv = (UV - mask_rect.xy) / rect_size;
	float inside = (
		step(0.0, mask_uv.x)
		* step(mask_uv.x, 1.0)
		* step(0.0, mask_uv.y)
		* step(mask_uv.y, 1.0)
	);
	float special = texture(mask_texture, clamp(mask_uv, vec2(0.0), vec2(1.0))).r * inside;

	// 圆角矩形 SDF：dist<0 在内、>0 在外，1px 过渡抗锯齿。
	vec2 half_size = max(rect_size_px, vec2(1.0)) * 0.5;
	float radius = clamp(corner_radius_px, 0.0, min(half_size.x, half_size.y));
	vec2 q = abs(UV * max(rect_size_px, vec2(1.0)) - half_size) - (half_size - vec2(radius));
	float dist = length(max(q, vec2(0.0))) - radius;
	float rounded = 1.0 - smoothstep(-0.5, 0.5, dist);

	COLOR = vec4(0.0, 0.0, 0.0, dim_alpha * (1.0 - special) * rounded);
}
