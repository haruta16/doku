shader_type canvas_item;
render_mode unshaded;

// pre_cat_fx 组2「闪亮登场」的**黑色蒙层**。铺满整个 viewport,画在棋盘之上、光线层之下。
//
// 需求口径的图层模型(2026-09-15 定,自下而上):
//   ① 原始底图(游戏画面)
//   ② 黑色蒙层 —— 纯黑、约 60% 不透明,**以镂空.png 作反向 alpha 遮罩**   ← 本 shader
//   ③ 光线.png ┐ 这两层构成一个**图层组**:组内按滤色(Screen)互叠,
//   ④ 高亮.png ┘ **组的结果**再以正常混合叠到②                          ← pre_cat_spotlight_light
//   ⑤ 灯.png    中心对准光束起点                                        ← 普通 TextureRect
//   ⑥ 预放猫镜像 最上层,压在蒙层与光之上                                ← AnimatedSprite2D
//
// ⚠️ **③④ 的滤色只在组内生效、不作用于底色**。曾经把整层 Screen 到底色上,高亮直接变纯白 ——
//    Screen 会压平通道差,而「黄」的本质就是 B 低于 R/G。详见 pre_cat_spotlight_light 文件头。
//
// ⚠️ 别再把 ②③④ 合进一个 shader 手工做 over 合成。上一版就是那样(压暗 + 亮光 + 抠洞同一
//    pass,还给抠洞区单独一份 light_alpha),结果是「猫脸被暖光洗白」「抠洞里叠光圈颜色」这类
//    与图层模型不符的行为,靠加参数越修越偏。②⑤⑥ 现在各自是独立 CanvasItem、由 GPU 按正常
//    混合逐层叠,语义与美术 PSD 一一对应;③④ 合在同一个 pass 是**图层组语义**要求的
//    (组内混合必须先压平成单层才能 over 上去),不是退回手工合成。
//
// 「反向 alpha 遮罩」= 遮罩 alpha 越高、蒙层越透:`out_a = layer_a * (1 - knock_a)`。
// **直接用遮罩自己的 alpha,不做 smoothstep 重映射** —— 那是上一版为了「把光圈压在镂空边缘」
// 引入的,现在光圈是独立图层、不再需要跟镂空的边界对齐。
//
// 蒙层不透明度不走 uniform,而是取顶点色 alpha(= ColorRect.color.a × modulate.a),
// 于是淡入淡出直接改 `modulate.a` 即可,不必每帧 set_shader_parameter。
//
// ⚠️ 刻意没有圆角矩形 SDF 裁剪(board_pattern_dim.gdshader 有):那是为「压暗只铺棋盘矩形」
//    准备的,本层铺全屏。若日后把压暗范围改回棋盘矩形,必须把那段加回来,否则四角露直角暗块。

// 镂空遮罩。只用 alpha(其 rgb 恒为 #18130c、与合成无关)。
uniform sampler2D knock_tex : filter_linear, repeat_disable;
// 本层的屏幕像素尺寸(UV 是 [0,1],几何都在像素空间算)。
uniform vec2 rect_size_px = vec2(1.0, 1.0);
// 镂空的中心与边长(屏幕像素)。中心对准猫格,边长按需求固定 522(1080×2400 基线)。
uniform vec2 knock_center_px = vec2(0.0, 0.0);
uniform float knock_size_px = 1.0;
// 镂空强度(0=不抠、整屏满额压暗;1=按 knock_tex 满额抠)。由业务侧跟「光强」同步驱动 ——
// 落幕阶段光强为 0 时不抠洞,避免猫处「末端」先于光束整体提前露亮;瞄准阶段随光一起淡入。
uniform float knock_alpha = 0.0;

void fragment() {
	vec2 px = UV * rect_size_px;
	vec2 knock_uv = (px - knock_center_px) / max(knock_size_px, 0.0001) + vec2(0.5);
	// 出界记 0(= 不抠、保持满额压暗)。step 乘法而非 if:避免分支。
	float in_knock = (
		step(0.0, knock_uv.x) * step(knock_uv.x, 1.0)
		* step(0.0, knock_uv.y) * step(knock_uv.y, 1.0)
	);
	float knock_a = texture(knock_tex, clamp(knock_uv, vec2(0.0), vec2(1.0))).a * in_knock;
	COLOR = vec4(0.0, 0.0, 0.0, COLOR.a * (1.0 - knock_a * knock_alpha));
}
