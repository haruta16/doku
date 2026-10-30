shader_type canvas_item;

/// 圆环进度：按 progress(0..1) 只显示原图的一段圆弧（从起点角度到进度角度）。
///
/// 中间段直接按原 UV 采样，完整保留原图的径向剖面（环体 + 边缘光晕）。
/// 两端不做角度硬切，而是收成半圆「圆头」：利用圆环（近似）旋转对称的特性——
/// 端帽区任一像素到「端点中线点」的距离 dcap，等价于该像素在环横截面上到中线的距离；
/// 于是按 (ring_radius + dcap) 反向采样原图的径向剖面，直接得到圆头 + 原图光晕，
/// 无需人工硬边，衰减过程中端点始终圆润且光晕与主体一致。
///
/// progress    = 进度 0..1（动画轨道驱动这个参数）
/// start_deg   = 起点角度，0=正上方12点，顺时针为正
/// clockwise   = 是否顺时针填充
/// ring_radius = 环中线半径（UV 单位，中心=0.5），端帽圆心落在此半径上（本图实测≈0.413）

// fill≈0 时用于判定「整体不显示」的下限，避免浮点毛刺。
const float EPS = 0.0001;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float start_deg : hint_range(-360.0, 360.0) = 0.0;
uniform bool clockwise = true;
uniform float ring_radius : hint_range(0.0, 0.5) = 0.413;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	vec2 p = UV - vec2(0.5);
	float r = length(p);

	float ang = atan(p.x, -p.y);        // 0=正上方，顺时针递增
	if (ang < 0.0) ang += TAU;

	float start = radians(start_deg);
	float rel = clockwise ? (ang - start) : (start - ang);
	rel = mod(rel, TAU);
	if (rel < 0.0) rel += TAU;

	float fill = progress * TAU;

	// 主体：rel ∈ [0, fill] 直接用当前像素（径向剖面由原图 alpha 决定，光晕天然保留）。
	bool in_body = (rel <= fill);

	if (in_body) {
		COLOR = vec4(col.rgb, col.a * COLOR.a * step(EPS, fill));
	} else {
		// 端帽：取到最近端点的角差（起点端 / 进度端共用一套逻辑）。
		float d_end = rel - fill;           // 顺沿到「进度端」的角差
		float d_start = TAU - rel;          // 反向到「起点端」的角差
		float ang_gap;
		float ep_ang;                       // 该端点的中线角度
		if (d_end <= d_start) {
			ang_gap = d_end;
			ep_ang = clockwise ? (start + fill) : (start - fill);
		} else {
			ang_gap = d_start;
			ep_ang = start;
		}

		// dcap = 像素到「端点中线点」的平面距离（径向偏移 dr 与 切向弧长 合成）。
		float dr = r - ring_radius;
		float dt = r * ang_gap;
		float dcap = sqrt(dr * dr + dt * dt);

		// 反向采样：在端点中线方向、半径 (ring_radius + dcap) 处取原图径向剖面。
		// 该点必落在可见主体上，采到的正是「距中线 dcap」应有的 alpha（含光晕渐变）。
		vec2 dir = vec2(sin(ep_ang), -cos(ep_ang));
		vec2 cap_uv = vec2(0.5) + dir * (ring_radius + dcap);
		vec4 cap_col = texture(TEXTURE, cap_uv);

		float a = cap_col.a * COLOR.a * step(EPS, fill);
		COLOR = vec4(cap_col.rgb, a);
	}
}
