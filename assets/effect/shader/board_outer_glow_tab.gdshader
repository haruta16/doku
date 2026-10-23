shader_type canvas_item;
render_mode blend_mix, unshaded;

// board_outer_glow.gdshader 的「带顶部凸舌」变体：轮廓 = 棋盘圆角矩形 ∪ 接在棋盘顶边上的凸舌
// （normal_top_ui 里「贴棋盘」那条进度条的白底），接缝处带内凹过渡圆弧。
//
// ⚠️ 与基础版是**两个文件、运行时按需换用**（BoardOuterGlow._sync_geometry 有凸舌时才把
// 材质的 shader 换成本文件，无凸舌换回基础版）。刻意不合并成一个 shader 加 `if`：那会改动
// 全体用户（含全部对照组）每帧跑的那份 GLSL，实测 GPU 编译结果会漂出 1/255 级的像素差。
// 代价是前半段（uniform / rounded_rect_distance / 采样）与基础版重复 —— **改基础版的 SDF 或
// 采样逻辑时必须同步这里**。
//
// 发光的明暗/渐变全部来自 glow_profile，不在 Shader 内生成模糊或渐变。
// 所有几何都由 BoardOuterGlow._sync_geometry 换算成面板局部像素后写入，shader 不认识任何页面节点。
uniform sampler2D glow_profile : source_color, hint_default_transparent, filter_linear, repeat_disable;
uniform vec2 panel_size_px = vec2(1136.0);
uniform vec2 board_size_px = vec2(1008.0);
uniform float corner_radius_px : hint_range(0.0, 128.0, 1.0) = 30.0;
uniform float profile_span_px : hint_range(1.0, 256.0, 1.0) = 64.0;

// 棋盘中心相对面板中心的偏移：有凸舌时面板只向上扩，棋盘中心不再落在面板正中。
uniform vec2 board_center_shift_px = vec2(0.0);
// 凸舌白底的直边矩形（xy = 左上角，zw = 宽高）。底边刻意伸进棋盘内，让两条竖直边一路直到过渡圆弧起点。
uniform vec4 tab_rect_px = vec4(0.0);
// 凸舌顶部两个凸圆角的半径。
uniform float tab_corner_radius_px : hint_range(0.0, 128.0, 1.0) = 40.0;
// 凸舌竖直边与棋盘之间那段内凹过渡圆弧的半径。
uniform float tab_fillet_radius_px : hint_range(0.0, 128.0, 1.0) = 30.0;
// 内凹圆弧与之相切的水平基线（面板局部 y）。美术把它画在棋盘顶边**以下**几像素，
// 圆弧在到达基线之前就被棋盘白底切断 —— 与白底贴图的真实轮廓一致，不是 bug。
uniform float tab_flare_baseline_px = 0.0;

float rounded_rect_distance(vec2 point, vec2 half_size, float radius) {
	float safe_radius = clamp(radius, 0.0, min(half_size.x, half_size.y));
	vec2 offset = abs(point) - (half_size - vec2(safe_radius));
	return length(max(offset, vec2(0.0))) + min(max(offset.x, offset.y), 0.0) - safe_radius;
}

float box_distance(vec2 point, vec2 half_size) {
	vec2 offset = abs(point) - half_size;
	return length(max(offset, vec2(0.0))) + min(max(offset.x, offset.y), 0.0);
}

// 两个 SDF 的并集，并在二者相交的内凹拐角处补一段半径 radius 的圆弧过渡（hg_sdf 的 fOpUnionRound）。
// 拐角之外退化成普通 min，两形状各自的外轮廓不受影响。
float union_round(float a, float b, float radius) {
	vec2 u = max(vec2(radius - a, radius - b), vec2(0.0));
	return max(radius, min(a, b)) - length(u);
}

// 凸舌轮廓：顶部圆角矩形 + 竖直边与水平基线之间的内凹过渡圆弧。
// 基线只在凸舌两侧各 fillet 宽的范围内有效，故做成有限宽的矩形而不是无限半平面 ——
// 半平面会在远离凸舌处（棋盘自身的圆角附近）压过棋盘轮廓。
float tab_distance(vec2 pixel) {
	vec2 tab_half = tab_rect_px.zw * 0.5;
	vec2 tab_center = tab_rect_px.xy + tab_half;
	float d_tab = rounded_rect_distance(pixel - tab_center, tab_half, tab_corner_radius_px);
	float fillet = tab_fillet_radius_px;
	vec2 flare_half = vec2(tab_half.x + fillet, tab_rect_px.w);
	vec2 flare_center = vec2(tab_center.x, tab_flare_baseline_px + flare_half.y);
	float d_flare = box_distance(pixel - flare_center, flare_half);
	return union_round(d_tab, d_flare, fillet);
}

void fragment() {
	vec4 canvas_color = COLOR;
	vec2 pixel = UV * panel_size_px;
	vec2 centered = pixel - panel_size_px * 0.5 - board_center_shift_px;
	float distance_to_board = rounded_rect_distance(centered, board_size_px * 0.5, corner_radius_px);
	// 棋盘 ∪ 凸舌。凸舌自带的过渡圆弧在棋盘顶边处被棋盘白底切断，这里的 min 复刻的就是那一刀。
	float distance_to_shape = min(distance_to_board, tab_distance(pixel));

	// 贴图底边固定贴住白底真实轮廓，向外按整张贴图展开。
	float profile_v = 1.0 - distance_to_shape / max(profile_span_px, 0.0001);
	if (profile_v >= 0.0 && profile_v <= 1.0) {
		vec4 profile_color = texture(glow_profile, vec2(0.5, profile_v));
		COLOR = canvas_color * profile_color;
	} else {
		COLOR = vec4(0.0);
	}
}
