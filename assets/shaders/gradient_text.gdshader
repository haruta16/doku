shader_type canvas_item;

/// 文字线性渐变:把挂载节点(Label / RichTextLabel)的文字颜色替换为
/// start_color → end_color 的线性渐变,字形 alpha 保留。
///
/// 渐变位置在 **vertex 阶段按节点局部坐标** 计算(顶点属性即局部空间,早于
/// model_matrix 变换),因此:
/// - 节点移动 / CanvasLayer / viewport stretch / 父级入场动画都不影响渐变范围
/// - 无需每帧同步全局 rect;仅节点 size 变化时由 GradientLabel 同步 rect_size
///
/// direction 分量约定取 0/1:(0,1)=上→下 (1,0)=左→右 (1,1)=左上→右下;
/// 用「分量和」归一化,对角方向也能恰好铺满整个节点。反方向请交换两端色,不传负分量。
///
/// 映射语义(重要):渐变按**节点矩形**归一化(同 CSS background-clip:text 的元素盒语义),
/// 不是文字墨迹范围 —— 行盒含 ascent/descent 空隙(拉丁字形墨迹约占行盒 50~80%),
/// 且文字因 alignment 居中/偏移时墨迹落在渐变中段。表现为端点色不满幅,是预期行为;
/// 要端点更满就把节点框做紧(或按视觉调 start/end 色)。引擎无逐 glyph 墨迹边界 API,
/// 不做墨迹级映射。
///
/// 注意(整体染色):shader 作用于该节点的全部绘制输出 —— Label 的 shadow /
/// outline 会被一并染成渐变色。需要「渐变字 + 纯色描边」时叠放两个同 text 的
/// Label:底层开 outline 且 font_color 透明,顶层用渐变。
///
/// 配套脚本:scripts/module/ui/extensions/gradient_label.gd(自动建 material + 同步 uniform)。

uniform vec4 start_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 end_color : source_color = vec4(0.55, 0.55, 0.55, 1.0);
uniform vec2 direction = vec2(0.0, 1.0);

// 节点尺寸(局部空间),由脚本在 size 变化时同步;0 会被钳到 0.001 防除零
uniform vec2 rect_size = vec2(100.0, 100.0);

varying float grad_t;

void vertex() {
	vec2 safe_size = vec2(max(rect_size.x, 0.001), max(rect_size.y, 0.001));
	float sum = max(direction.x + direction.y, 0.001);
	grad_t = clamp(dot(VERTEX / safe_size, direction) / sum, 0.0, 1.0);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 grad_rgb = mix(start_color.rgb, end_color.rgb, grad_t);
	// 完整复刻原生 canvas 管线 color * texture 的乘法公式,仅把基色从 font_color 换成渐变色:
	// 字体图集是 LA8/R8 格式,字形覆盖度在亮度(rgb)而非 alpha 通道,用 tex.rgb 相乘对
	// 覆盖度所在通道不敏感(antialiasing 边缘半覆盖同样正确)。顶点色 rgb 继续作乘色,
	// 保留 font_color 调色 / modulate 淡入的原生语义。
	COLOR = vec4(grad_rgb * COLOR.rgb * tex.rgb, COLOR.a * tex.a);
}
