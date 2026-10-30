shader_type canvas_item;

/// UV 流动通用特效材质
/// 使用前提：节点 Texture > Repeat = Enabled，Filter = Linear
/// scroll_speed : 流动方向和速度（单位：UV/秒，正值向右/向下）

uniform vec2 scroll_speed = vec2(0.1, 0.0);

void fragment() {
	COLOR = texture(TEXTURE, UV + scroll_speed * TIME) * COLOR;
}
