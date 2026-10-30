shader_type canvas_item;

/// 圆环「光晕层」进度遮罩：配合 ring_progress 主环一起衰减。
/// 光晕本身柔和、无锐利边缘，所以这里不做圆头反向采样（那会在宽光晕上切出直角硬边），
/// 只按「角度」显示 rel ∈ [0, fill] 的扇形，两端做角度软边即可，视觉上自然渐隐。
///
/// progress   = 进度 0..1（与主环共用同一条动画轨道）
/// start_deg  = 起点角度，0=正上方12点，顺时针为正
/// clockwise  = 是否顺时针填充
/// edge_soft  = 端点角度软边宽度（弧度），越大端头越柔和

// fill≈0 时用于判定「整体不显示」的下限，避免浮点毛刺。
const float EPS = 0.0001;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float start_deg : hint_range(-360.0, 360.0) = 0.0;
uniform bool clockwise = true;
uniform float edge_soft : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	vec2 p = UV - vec2(0.5);

	float ang = atan(p.x, -p.y);        // 0=正上方，顺时针递增
	if (ang < 0.0) ang += TAU;

	float start = radians(start_deg);
	float rel = clockwise ? (ang - start) : (start - ang);
	rel = mod(rel, TAU);
	if (rel < 0.0) rel += TAU;

	float fill = progress * TAU;

	// 角度遮罩：以填充区中心 half 为原点，把角差折到连续区间 [-PI, PI]。
	// 这样起点端(尾部)外侧是连续的负角，进度端(头部)外侧是连续的正角，
	// 两端软边完全对称、都不会被 mod 截断 —— 修掉尾部切边。
	float half = fill * 0.5;
	float dc = rel - half;                     // 以中心为原点的角差
	dc = mod(dc + PI, TAU) - PI;               // 折到 [-PI, PI]，两端连续
	float d = abs(dc);
	float mask = 1.0 - smoothstep(half, half + edge_soft, d);
	mask *= step(EPS, fill);

	float a = col.a * mask * COLOR.a;
	COLOR = vec4(col.rgb, a);
}
