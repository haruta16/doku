# 首页背景光晕：只在 _draw 里画三层同心半透明圆，无逻辑、无子节点
extends Control


# 绘制光晕：圆心固定在控件宽度中点、高度 35% 处，由外到内三层叠加
func _draw() -> void:
	var cx: float = size.x * 0.5  # 圆心 X：控件宽度中点
	var cy: float = size.y * 0.35  # 圆心 Y：控件高度的 35%（偏上）
	draw_circle(Vector2(cx, cy), 581.0, Color(1.0, 1.0, 1.0, 0.18))  # 最外层，半径 581 像素，最淡（alpha 0.18）
	draw_circle(Vector2(cx, cy), 443.0, Color(1.0, 1.0, 1.0, 0.28))  # 中层，半径 443 像素
	draw_circle(Vector2(cx, cy), 332.0, Color(1.0, 1.0, 1.0, 0.42))  # 最内层，半径 332 像素，最亮（alpha 0.42）
