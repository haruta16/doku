shader_type canvas_item;

/// 线性渐变 + 圆角矩形遮罩通用材质
/// grad_p0 / grad_p1 : UV 空间渐变起止点（来自 figma gradientTransform）
/// pos0 / pos1       : figma stop 位置(支持 0.0/1.0 之外的非默认 stop)
/// corner_radius      : 4 角圆角半径(像素),CSS 同序 vec4(TL, TR, BR, BL)。
///                     vec4(0)=全直角,vec4(R)=4 角等圆,各分量独立支持非对称圆角
///                     (典型场景:figma banner 顶部圆角 / 底部直角)
/// stroke_color_left/right : 描边渐变两端色。两端同色 = 单色 stroke;两端 a=0 关闭描边
/// stroke_width            : 描边宽度(像素)。<=0 时关闭描边。
///                          仅支持 figma strokeAlign=INSIDE(默认);OUTSIDE/CENTER 由 bridge 端退回 PNG 路径
///                          stroke 渐变方向复用 fill 的 grad_p0/p1(figma 上 fill+stroke 渐变方向
///                          通常一致;无 fill 时 fill 端两端同色,grad_p0/p1 专给 stroke 用)
/// 注:Godot 4 shader 自动管精度,不需要 `precision highp float;`(那是 raw GLSL 语法)

uniform vec4 color_left : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_right : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 grad_p0 = vec2(0.0, 0.0);
uniform vec2 grad_p1 = vec2(1.0, 0.0);
uniform float pos0 = 0.0;
uniform float pos1 = 1.0;
uniform vec4 corner_radius = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 stroke_color_left : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 stroke_color_right : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float stroke_width = 0.0;
/// rect_size 由调用方(node_builder.gd)显式传入节点像素尺寸,
/// 替代 TEXTURE_PIXEL_SIZE — 后者对 ColorRect 不可靠(内部用 1×1 白纹理)。
uniform vec2 rect_size = vec2(100.0, 100.0);

// Godot 4 无 MODULATE 内置量。vertex 里的 COLOR = modulate * self_modulate（含 GUI 透明度），
// 透 varying 带进 fragment，末尾乘上去，让 Modulate / Self Modulate 生效（否则覆写 COLOR 会吞掉它）。
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	// 渐变插值：t_raw = (UV - p0) · dir / |dir|^2,再按 stop 位置 remap 到 [0,1]
	vec2 dir = grad_p1 - grad_p0;
	float denom = dot(dir, dir);
	float t_raw = 0.0;
	if (denom > 0.00000001) {
		t_raw = clamp(dot(UV - grad_p0, dir) / denom, 0.0, 1.0);
	}
	float t = clamp((t_raw - pos0) / max(pos1 - pos0, 0.00000001), 0.0, 1.0);
	vec4 color = mix(color_left, color_right, t);

	// 圆角矩形 SDF (per-corner):按象限选 corner_radius 分量
	// p 在中心坐标系 → x>0 右半,y>0 下半,对应 CSS 顺时针 4 角:
	//   x<0 y<0 → .x (TL)   x>0 y<0 → .y (TR)
	//   x>0 y>0 → .z (BR)   x<0 y>0 → .w (BL)
	vec2 pos_px = UV * rect_size;
	vec2 b = rect_size * 0.5;
	vec2 p = pos_px - b;
	vec2 rxy = (p.x > 0.0) ? corner_radius.yz : corner_radius.xw;
	float r = (p.y > 0.0) ? rxy.y : rxy.x;
	r = min(r, min(b.x, b.y));
	vec2 q = abs(p) - b + r;
	float dist = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;

	// 节点本体 alpha mask:dist<=0 完全填充,边缘 1px AA
	float fill_mask = clamp(0.5 - dist, 0.0, 1.0);
	// 节点内部(扣掉 INSIDE stroke 后)mask:dist<=-stroke_width
	float inner_mask = clamp(0.5 - (dist + stroke_width), 0.0, 1.0);
	// stroke 环带:fill 但不在 inner 内
	float stroke_band = fill_mask - inner_mask;

	// stroke 渐变色用同一个 t 插值,与 fill 共享渐变方向
	vec4 stroke_color = mix(stroke_color_left, stroke_color_right, t);
	// stroke_color.a=0 / stroke_width=0 时 stroke_band 影响自动衰减为 0,fill 完整可见
	vec3 final_rgb = mix(color.rgb, stroke_color.rgb, stroke_band * stroke_color.a);
	// alpha 分区合成:fill 区取 fill alpha,stroke 区取两者 max
	// 旧逻辑 (color.a * fill_mask) 在 fill 透明 + stroke 不透明时把 stroke 区 alpha 错杀为 0,
	// 改 max 后:stroke a=0 退化为 color.a * fill_mask(向后兼容);fill 透明 + stroke 不透明
	// 时 stroke 区 alpha = stroke.a(支持纯 stroke 装饰节点,如 figma btn_pop_line 类)
	float final_a = max(color.a * fill_mask, stroke_color.a * stroke_band);

	COLOR = vec4(final_rgb, final_a) * v_modulate;
}
