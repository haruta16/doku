## 触点调试层：绘制触点中心与覆盖范围圆，不参与实际输入命中。
class_name TouchPointDebugOverlay
extends Control

const _DIAMETER_IN_CELLS: float = 2.0

const _CIRCLE_COLOR: Color = Color(0.7, 0.55, 0.95, 0.45)

const _CENTER_DOT_COLOR: Color = Color(0.45, 0.25, 0.8, 0.85)
const _CENTER_DOT_RADIUS: float = 4.0

var _enabled: bool = false

var _points: Array[Vector2] = []


## 忽略鼠标输入并置于棋盘调试层上方。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	z_index = 101


## 切换显示；关闭时清空旧触点避免下次重新出现。
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		_points.clear()
	queue_redraw()


## 显示中才接收触点快照，内容变化后复制数组并重绘。
func update_points(points: Array[Vector2]) -> void:
	if not _enabled:
		return
	if _points == points:
		return
	_points = points.duplicate()
	queue_redraw()


## 以棋盘格像素大小为基准，为每个触点绘制半透明范围圆和中心点。
func _draw() -> void:
	if not _enabled or _points.is_empty():
		return
	var radius: float = float(BoardView.CELL_PX) * _DIAMETER_IN_CELLS * 0.5
	for point: Vector2 in _points:
		draw_circle(point, radius, _CIRCLE_COLOR)
		draw_circle(point, _CENTER_DOT_RADIUS, _CENTER_DOT_COLOR)
