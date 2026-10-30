shader_type canvas_item;

// 错误色区高亮的光晕描边调色(美术方案 2026-10-20-region-alert-outline-glow-design):
// 线条贴图中心的白芯保持原色,两侧辉光换成 glow_tint。白芯按像素「最小通道」判定(越接近纯白越大):
// et_line_005 黑辉光约 0、白芯 1.0。片元阶段引擎已把贴图乘进 COLOR,这里重新采原始贴图;
// 节点 modulate(呼吸透明度)经 vertex_tint 从顶点阶段带过来。

// 辉光颜色;脚本按 Color 原值写入,不做色彩空间转换
uniform vec4 glow_tint = vec4(1.0, 1.0, 1.0, 1.0);
// 最小通道低于 core_from 全按辉光染色,高于 core_to 全保留原色,之间平滑过渡
uniform float core_from : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float core_to : hint_range(0.0, 1.0, 0.01) = 1.0;

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float whiteness = min(texel.r, min(texel.g, texel.b));
	float core = smoothstep(core_from, core_to, whiteness);
	vec3 rgb = mix(glow_tint.rgb, texel.rgb, core);
	float alpha = texel.a * mix(glow_tint.a, 1.0, core);
	COLOR = vec4(rgb, alpha) * vertex_tint;
}
