shader_type canvas_item;

/// 文本 2-stop 线性渐变填充。挂在 Label 上：按字形在 Label 局部空间的位置采样渐变色，
/// 用字形覆盖 alpha (texture(TEXTURE,UV).a) 作遮罩。grad_p0/p1 与 stop 位置沿用 shape 渐变
/// (linear_gradient.gdshader) 的 UV[0,1] 约定，由 node_builder 从 figma gradientHandles 传入。
///
/// ⚠ Godot 的 Label 描边与字体填充同 material、同一趟绘制，本 shader 会把描边也染成渐变色。
/// 需要保留原描边时，node_builder 把节点拆成 描边Label + 渐变填充Label 两层，本 shader 只挂
/// 后者（前者用原生 outline 绘制），见 node_builder.gd _wrap_text_gradient_outline。

uniform vec4 color_left : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_right : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 grad_p0 = vec2(0.0, 0.0);
uniform vec2 grad_p1 = vec2(0.0, 1.0);
uniform float pos0 = 0.0;
uniform float pos1 = 1.0;
/// rect_size 由 node_builder 传入节点像素尺寸；VERTEX 是 Label 局部坐标(左上原点，像素)。
uniform vec2 rect_size = vec2(100.0, 100.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// 与 linear_gradient.gdshader 同套：t_raw = (uv - p0)·dir / |dir|^2，再按 stop 位置 remap。
	vec2 uv = v_local / max(rect_size, vec2(1.0, 1.0));
	vec2 dir = grad_p1 - grad_p0;
	float denom = dot(dir, dir);
	float t_raw = 0.0;
	if (denom > 0.00000001) {
		t_raw = clamp(dot(uv - grad_p0, dir) / denom, 0.0, 1.0);
	}
	float t = clamp((t_raw - pos0) / max(pos1 - pos0, 0.00000001), 0.0, 1.0);
	vec4 grad = mix(color_left, color_right, t);

	// 字形覆盖率（SDF/位图字体 alpha 通道），乘节点自身 modulate alpha (COLOR.a) 保 figma 图层不透明度。
	float cov = texture(TEXTURE, UV).a;
	COLOR = vec4(grad.rgb, grad.a * cov * COLOR.a);
}
