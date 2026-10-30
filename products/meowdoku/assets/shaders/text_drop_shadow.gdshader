shader_type canvas_item;

// 文本 drop shadow:替代 Godot 原生 shadow_outline_size(硬遮罩,无渐变衰减)。
// 挂在包裹文本节点的 CanvasGroup 上,靠 hint_screen_texture 读取该 CanvasGroup 自己
// 合并渲染出的字形 alpha buffer,多 tap 网格采样做近似高斯模糊 + 偏移,叠加在原始
// 清晰像素下方。CanvasGroup 语义保证这里的 SCREEN_TEXTURE/SCREEN_UV 只包含自己子树
// 内容,不会读到场景里其它元素。
//
// spread 没有独立几何实现(未对字形做真正的形态学扩张),直接并入 blur 半径近似——
// 视觉上跟 Figma 分不太出来,已知简化,效果不够时再补真 spread。
// blur → 像素半径的换算系数(TEXT_SHADOW_BLUR_SCALE,见 node_builder.gd)需要肉眼对比
// Figma 截图标定,当前只是起始值。

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 shadow_offset = vec2(0.0, 0.0);
uniform float blur_px = 0.0;
uniform float spread_px = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

const int GRID = 5;
const float GRID_HALF = float(GRID - 1) * 0.5;

float sample_alpha(vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(screen_tex, uv).a;
}

vec4 src_over(vec4 top, vec4 bottom) {
	float out_a = top.a + bottom.a * (1.0 - top.a);
	vec3 out_rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
	if (out_a > 0.0001) {
		out_rgb /= out_a;
	}
	return vec4(out_rgb, out_a);
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec2 offset_uv = shadow_offset * texel;
	float radius = max(blur_px + spread_px, 0.001);
	float sigma = max(radius * 0.5, 0.001);

	float shadow_alpha = 0.0;
	float weight_sum = 0.0;
	for (int y = 0; y < GRID; y++) {
		for (int x = 0; x < GRID; x++) {
			vec2 grid_pos = vec2(float(x), float(y)) - GRID_HALF;
			vec2 tap_px = (grid_pos / max(GRID_HALF, 0.001)) * radius;
			float w = exp(-dot(tap_px, tap_px) / (2.0 * sigma * sigma));
			shadow_alpha += sample_alpha(SCREEN_UV - offset_uv + tap_px * texel) * w;
			weight_sum += w;
		}
	}
	shadow_alpha /= max(weight_sum, 0.0001);

	vec4 shadow = vec4(shadow_color.rgb, shadow_color.a * shadow_alpha);
	vec4 original = texture(screen_tex, SCREEN_UV);
	// CanvasGroup 缓冲是预乘 alpha:original.rgb 已 = 颜色×alpha。src_over 按直通 alpha 运算
	// (再乘一次 top.a),边缘半透明像素(描边 AA 环)会被二次压暗成灰/黑边。先解预乘还原直通
	// alpha,src_over 与最终 canvas 直通混合才一致。不透明内部 a=1 时该除法为恒等,无影响。
	if (original.a > 0.0001) {
		original.rgb /= original.a;
	}
	COLOR = src_over(original, shadow);
}
