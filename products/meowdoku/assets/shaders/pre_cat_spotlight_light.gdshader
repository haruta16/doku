shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// pre_cat_fx 组2「闪亮登场」的**光层**:光线.png(③)与高亮.png(④)当作一个 **PSD 图层组**
// 合成 —— 组内按 `blend_mode`(默认滤色 Screen)互叠,**组的合成结果再以正常混合(over)
// 叠到已压暗的画面上**。铺满整个 viewport,画在黑色蒙层之上、灯之下。
// 完整图层模型见 pre_cat_spotlight_dim.gdshader 的文件头。
//
// ⚠️ **「滤色」只作用在③④ 之间,不作用于底色**(需求口径 2026-09-15,当日下午修正)。
//    最初把整层 Screen 到底色上,结果高亮变纯白 —— Screen 逐通道趋近 1、会把通道差压平,
//    而「黄」的本质就是 B 明显低于 R/G。实测:高亮图 rgb=(0.875,0.651,0.082),叠在镂空区
//    近白底(≈0.95)上,三通道全被推到 0.99 上下 ⇒ 色相丢失、只剩亮度。
//    **Screen「永不过曝」这句只对亮度成立、对色相不成立** —— 这是当时的认知盲区。
//    现在组结果走 over,底色只被按组 alpha 遮蔽、不参与提亮,色相原样保留。
//
// ── 为什么③④ 仍必须在同一个 pass ──────────────────────────────────
// 理由已经**换了**:不再是「screen_texture 不能链式叠加」那条(现在根本不读 dst),
// 而是**图层组的语义要求**:组内混合必须先压平成一份「预乘色 + 并集 alpha」,才能作为
// 单一图层 over 到底色。若把③④ 拆成两个独立 CanvasItem,GPU 只会各自 over 到画面上 ——
// 那就退化成 blend_mode=0,组内的滤色无从表达(重叠处高亮直接盖掉光线、亮度反而不升)。
//
// 组合成用 W3C 合成公式(source = ④ 高亮,backdrop = ③ 光线,组底为全透明):
//   ag = ap + ab*(1-ap)                                   ← 并集 alpha
//   Co = ap*(1-ab)*Cp + ab*(1-ap)*Cb + ap*ab*B(Cb,Cp)     ← **预乘**色
// 自检:ab=0 → (ap*Cp, ap);ap=0 → (ab*Cb, ab);两者皆 1 → (B, 1)。三个退化情形都对。
//
// 输出是**预乘 alpha**,故 `render_mode blend_premul_alpha`(硬件算 `dst*(1-a) + rgb`)。
// ⚠️ 别改回默认的 blend_mix:那条按非预乘解释 rgb,会把组内混合的结果又乘一次 alpha、
//    重叠处发暗。也别为了迁就 blend_mix 去做 `Co/ag` 反预乘 —— ag→0 处会数值炸开。
//
// 淡入淡出走 `light_alpha`:预乘表示下「整组淡出」= 预乘色与 alpha **同时**乘同一系数,
// 组内的混合比例分毫不变。⚠️ 不要改成只缩放 ab/ap —— 那会让重叠项 ap*ab 按平方衰减,
// 淡出过程中组内滤色的强度跟着掉,与「整组降不透明度」不是一回事。
// ⚠️ 也不能用 `modulate.a`:本 shader 整体覆写 COLOR、不读顶点色。

// 光线贴图。**尖端在上 = 灯端**,向下渐宽渐隐,故局部 v=0 取贴图顶边。
uniform sampler2D beam_tex : filter_linear, repeat_disable;
// 高亮贴图(猫处光池)。
uniform sampler2D pool_tex : filter_linear, repeat_disable;

// **组内**(③ 光线 ↔ ④ 高亮)的混合模式,与底色无关 —— 底色恒为正常混合。
// 0 = 正常混合(over) / 1 = 加色(Add) / 2 = 滤色(Screen)。与 fx2_spotlight.gd 的
// `light_blend_mode` 枚举一一对应,改一处必须同步另一处。
uniform int blend_mode : hint_range(0, 2) = 2;
// 整组的不透明度(淡入淡出用)。
uniform float light_alpha : hint_range(0.0, 1.0, 0.001) = 1.0;

uniform vec2 rect_size_px = vec2(1.0, 1.0);

// 灯锚点与光束末端(屏幕像素)。灯位固定不动,是光束旋转拉伸去找猫。
uniform vec2 beam_from_px = vec2(0.0, 0.0);
uniform vec2 beam_to_px = vec2(0.0, 1.0);
// 梯形起点(灯端,v=0)与**猫心处**的宽度(屏幕像素)。
uniform float beam_top_width_px = 1.0;
uniform float beam_bottom_width_px = 1.0;
// 猫心所在的 v。无延伸时 = 1.0;有延伸时 < 1.0(v=1 落在猫的更远处)。
// 宽度包络按它归一 ⇒「结束宽度」恒指猫心处;延伸段按同一斜率线性外推继续变宽。
// 若改回除以 1.0,一旦有延伸,猫处宽度就会小于设定值、高亮边缘漏在光束外。
uniform float beam_cat_v : hint_range(0.05, 1.0, 0.001) = 1.0;
// 贴图淡出的起点 v(= 光柱抵达高亮圈边缘处),由 GDScript 侧算好传入。
uniform float beam_fade_v : hint_range(0.0, 0.999, 0.001) = 0.9;
// 源贴图自身淡出的起点行(0~1),也是下面分段重映射的**分割点**。
// 实测该图 alpha 在 v≈0.10~0.70 间基本持平在峰值 0.44~0.46,过 0.70 后开始掉。
uniform float beam_tex_v_cap : hint_range(0.05, 1.0, 0.01) = 0.72;

// 高亮中心与边长(屏幕像素)。
uniform vec2 pool_center_px = vec2(0.0, 0.0);
uniform float pool_size_px = 1.0;


// 组内混合函数 B(backdrop, source):只算颜色,alpha 的合成由外面的 Porter-Duff 负责。
vec3 blend_in_group(vec3 cb, vec3 cs) {
	vec3 result = cs;                                     // 0 正常混合:取上层色
	vec3 add = clamp(cb + cs, vec3(0.0), vec3(1.0));      // 1 加色
	vec3 screen = 1.0 - (1.0 - cb) * (1.0 - cs);          // 2 滤色
	result = mix(result, add, step(0.5, float(blend_mode)));
	result = mix(result, screen, step(1.5, float(blend_mode)));
	return result;
}

void fragment() {
	vec2 px = UV * rect_size_px;

	// ── ③ 光线:把像素变换进「沿光束轴 v、垂直光束 u」的局部空间 ──
	vec2 axis = beam_to_px - beam_from_px;
	float axis_len = max(length(axis), 0.0001);
	vec2 dir = axis / axis_len;
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 rel = px - beam_from_px;
	float v = dot(rel, dir) / axis_len;
	float v_clamped = clamp(v, 0.0, 1.0);
	float beam_width_at_v = beam_top_width_px
		+ (beam_bottom_width_px - beam_top_width_px) * (v_clamped / max(beam_cat_v, 0.0001));
	float u = dot(rel, perp) / max(beam_width_at_v, 0.0001) + 0.5;
	// 贴图取样用分段重映射的 v(与宽度包络解耦):
	//   段 A  v ∈ [0, v_arrive] → 贴图 [0, cap]   保留灯端淡入 + 主体维持峰值
	//   段 B  v ∈ [v_arrive, 1] → 贴图 [cap, 1]   把贴图的淡出尾巴压进「进入高亮之后」
	// ⚠️ 2026-09-14/15 两轮踩坑,别再往回改:直接用真实 v 会让末端又宽又淡拉成一团雾、
	//    与猫断开;而把取样 v 封顶则是整段砍掉淡出、一直到猫心都是硬边。
	float v_arrive = clamp(beam_fade_v, 0.0, 0.999);
	float v_a = (v_clamped / max(v_arrive, 0.0001)) * beam_tex_v_cap;
	float v_b = mix(beam_tex_v_cap, 1.0,
		clamp((v_clamped - v_arrive) / max(1.0 - v_arrive, 0.0001), 0.0, 1.0));
	float v_tex = mix(v_b, v_a, step(v_clamped, v_arrive));
	// 出界处 alpha 记 0。step 乘法而不是 if:避免分支,也让边界自然截断。
	float in_beam = (
		step(0.0, u) * step(u, 1.0)
		* step(0.0, v) * step(v, 1.0)
	);
	vec4 beam_c = texture(beam_tex, clamp(vec2(u, v_tex), vec2(0.0), vec2(1.0)));
	float ab = beam_c.a * in_beam;

	// ── ④ 高亮:以猫格中心为心的正方 UV ──
	vec2 pool_uv = (px - pool_center_px) / max(pool_size_px, 0.0001) + vec2(0.5);
	float in_pool = (
		step(0.0, pool_uv.x) * step(pool_uv.x, 1.0)
		* step(0.0, pool_uv.y) * step(pool_uv.y, 1.0)
	);
	vec4 pool_c = texture(pool_tex, clamp(pool_uv, vec2(0.0), vec2(1.0)));
	float ap = pool_c.a * in_pool;

	// ── 组合成:④ 高亮(source)叠在③ 光线(backdrop)之上,组底全透明 ──
	// 顺序与图层表 ③→④ 一致。滤色 / 加色可交换,正常混合不可,故仍按图层顺序传参。
	float ag = ap + ab * (1.0 - ap);
	vec3 co = ap * (1.0 - ab) * pool_c.rgb
		+ ab * (1.0 - ap) * beam_c.rgb
		+ ap * ab * blend_in_group(beam_c.rgb, pool_c.rgb);

	// 整组淡入淡出:预乘色与 alpha 同乘,组内比例不变(理由见文件头)。
	COLOR = vec4(co * light_alpha, ag * light_alpha);
}
