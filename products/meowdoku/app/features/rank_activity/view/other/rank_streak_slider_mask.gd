## 连胜条移动高亮的自绘遮罩；把各档位外轮廓与连接段绘制成连续形状。

extends Control

var _shapes: Array = []
var _bridges: Array[Rect2] = []


func set_outline(shapes: Array, bridges: Array[Rect2]) -> void:
	_shapes = shapes
	_bridges = bridges
	queue_redraw()


func _draw() -> void:
	for shape in _shapes:
		draw_texture_rect(shape[0] as Texture2D, shape[1] as Rect2, false)
	for bridge in _bridges:
		draw_rect(bridge, Color.WHITE)
