shader_type canvas_item;

/// 文字线性渐变(CanvasGroup 版)。挂在包裹「字身绘制层」的 CanvasGroup 上,
/// 把该 CanvasGroup 合成出的像素替换为 gradient_start → gradient_end 的线性渐变,
/// 字形 alpha(含 AA 半覆盖)完整保留。
///
/// 为什么用 UV 而不是 VERTEX:CanvasGroup 先把子树渲染成一张离屏纹理再整体绘制,
/// 所以 UV 是「buffer 局部归一化坐标」—— 不随节点移动 / 入场动画流动,
/// 且子树里 draw_set_transform 的旋转已烘进像素。
/// 实测(Godot 4.6.1, opengl3):子树屏幕 x=50..230 + fit_margin=10 → buffer=[40,240],
/// 屏幕 x=55/140/225 对应 UV.x=0.0745/0.5020/0.9294,与 (x-40)/200 逐项吻合。
/// 反例:SCREEN_UV 是屏幕坐标(同场景下 x=55 → 0.1373 = 55/400),节点一动渐变就跟着漂。
///
/// 与 assets/shaders/gradient_text.gdshader 的分工:那份走 VERTEX,给普通 Label 用
/// (原生排版,支持多行 / autowrap / RichTextLabel);
/// 本份走 UV,给「内部有 draw_set_transform 旋转」的自绘 Label(SingleLineGlyphLabel)用 ——
/// draw_set_transform 的变换不进 VERTEX(实测 +100 平移后同一屏幕位置的 VERTEX.x
/// 仍是 10.2 而非 110.6),所以那份对 align_to_tangent 的曲线文字无效。
///
/// direction 分量约定取 0/1:(0,1)=上→下 (1,0)=左→右 (1,1)=左上→右下;
/// 用「分量和」归一化,对角方向也恰好铺满。反方向请交换两端色,不传负分量。

uniform vec4 gradient_start : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 gradient_end : source_color = vec4(0.55, 0.55, 0.55, 1.0);
uniform vec2 gradient_direction = vec2(0.0, 1.0);

/// CanvasGroup 自己合并渲染出的 buffer。**必须用 hint_screen_texture 读,不能用 TEXTURE**
/// —— 实测(Godot 4.6.1)在 CanvasGroup 上 texture(TEXTURE, UV) 拿不到该 buffer,
/// src.a 恒为 1.0,于是输出一个铺满 buffer 区域的实心渐变矩形而不是字形
/// (症状:每行不透明像素数恒定 = buffer 宽度,文字形状完全消失)。
/// 同款用法见 assets/shaders/text_drop_shadow.gdshader。
/// CanvasGroup 语义保证这里只读到自己子树的内容,不会读进场景里其它元素。
uniform sampler2D group_buffer : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	// 字形覆盖率取自 buffer(SCREEN_UV 是读该 buffer 的正确坐标),
	// 渐变位置取自 UV —— 两者刻意分工:
	//   UV 是 buffer 局部归一化坐标,不随节点移动 / 入场动画流动;
	//   SCREEN_UV 是屏幕坐标,拿它算渐变会让节点一动渐变就漂。
	//
	// 这里的 coverage 是**纯粹的字形覆盖率(含 AA 半覆盖)**:宿主在渐变开启时用
	// 纯白不透明画进 buffer(见 SingleLineGlyphLabel._layer_paint_color),不掺配置色的
	// alpha —— 透明度统一由下面两端色的 alpha 决定。
	float coverage = texture(group_buffer, SCREEN_UV).a;
	float direction_sum = max(gradient_direction.x + gradient_direction.y, 0.001);
	// clamp 放在 fragment(而非 vertex): varying 会在图元内线性插值,
	// 在 vertex 阶段 clamp 会让超出范围的图元内部渐变斜率被压缩失真。
	float ratio = clamp(dot(UV, gradient_direction) / direction_sum, 0.0, 1.0);
	// **rgb 与 alpha 都插值**:渐变开启后颜色数据完全由 gradient_start / gradient_end 提供,
	// 宿主侧对应的 *_color 属性(body_color / outline_color / shadow_color)此时不参与、
	// 并在 Inspector 里被 _validate_property 隐藏。故两端色的 alpha 差异可做「渐隐」。
	vec4 gradient_color = mix(gradient_start, gradient_end, ratio);
	// COLOR.a 是顶点色 alpha,承载 CanvasGroup 的 self_modulate —— SingleLineGlyphLabel.fade
	// 就是靠它传进来的。**必须乘上,否则整段淡入失效**(实测:漏掉它时 fade=0.5 与
	// fade=1.0 输出逐像素相同)。刻意只取 .a 不取 .rgb:颜色由 uniform 决定,
	// 不让顶点色调色,免得重演 gradient_text.gdshader 那边「font_color 非白就把
	// 渐变乘暗」的问题。
	float final_alpha = coverage * gradient_color.a * COLOR.a;
	// **rgb 必须是直通(un-premultiplied)、不要乘 final_alpha**。
	// 「读 buffer」与「写 COLOR」是两个相反方向,别混为一谈:
	//   读:CanvasGroup 的 backbuffer 里是预乘格式(所以上面只取 .a 当覆盖率是安全的);
	//   写:本 shader 输出后仍走一次标准 canvas 混合(本文件无 render_mode,默认 blend_mix),
	//      引擎会自己乘一遍 COLOR.a,故这里再乘就成了 rgb x a^2。
	// 官方约定见 Godot 4.6 CanvasGroup 文档里「复现内置 shader」那段:它显式
	// `c.rgb /= c.a` 解预乘后输出直通,且不声明 blend_premul_alpha。
	//
	// ⚠️ 曾经写成 `gradient_color.rgb * final_alpha`(2026-09-02 修):AA 半覆盖边缘
	// 每像素少了 a-a^2 = a(1-a) 份自身颜色(a=0.5 时缺 25%),缺口由纯黑填充 ——
	// 字形内部 a=1 恒等无损、字形外 a=0 无损,所以只在覆盖率约 50% 那一像素最深,
	// 表现为字身/描边、描边/阴影交界各一条约 1px 的暗线(胜利页标题实测:
	// 橙 204,108,14 与米白 254,242,227 之间出现 R=166,低于两端最小值 = 必有黑掺入)。
	// 同一个坑 text_drop_shadow.gdshader 早踩过并修成直通,那份的注释可对照。
	//
	// 等价改法是保留预乘输出 + 加 `render_mode blend_premul_alpha;`,已选直通以对齐
	// 官方与 text_drop_shadow;两者别混着用(声明了 premul 又输出直通会让 AA 边缘发亮)。
	COLOR = vec4(gradient_color.rgb, final_alpha);
}
