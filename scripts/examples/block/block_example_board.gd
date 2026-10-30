## 方块棋盘表现：悬停/拖拽预览，点击或放下方块提交意图。触摸由项目鼠标模拟转发。
extends Control

signal place_requested(row: int, col: int)

var session: RefCounted
var _snapshot: Dictionary = {}
var _preview: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(clear_preview)


func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	clear_preview()


func clear_preview() -> void:
	_preview = {}
	_hover_cell = Vector2i(-1, -1)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if session == null or _snapshot.is_empty():
		return
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_preview(event.position)
		place_requested.emit(_hover_cell.x, _hover_cell.y)
		accept_event()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or session == null:
		return false
	if typeof(data.get("kind")) != TYPE_STRING or data.kind != "block_piece":
		return false
	if typeof(data.get("round_id")) != TYPE_STRING or typeof(data.get("sequence")) != TYPE_INT:
		return false
	var current: Dictionary = session.current()
	if data.get("round_id") != current.get("round_id") or data.get("sequence") != current.get("next_sequence"):
		return false
	_update_preview(at_position)
	return bool(_preview.get("valid", false))


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	_update_preview(at_position)
	place_requested.emit(_hover_cell.x, _hover_cell.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_preview()


func _update_preview(position: Vector2) -> void:
	var side: float = minf(size.x, size.y)
	var origin := (size - Vector2.ONE * side) * 0.5
	var cell_size: float = side / maxf(1.0, float(_snapshot.get("size", 5)))
	_hover_cell = Vector2i(floori((position.y - origin.y) / cell_size), floori((position.x - origin.x) / cell_size))
	_preview = session.preview(_hover_cell.x, _hover_cell.y)
	queue_redraw()


func _draw() -> void:
	if _snapshot.is_empty():
		return
	var count: int = int(_snapshot.size)
	var side: float = minf(size.x, size.y)
	var origin := (size - Vector2.ONE * side) * 0.5
	var cell_size: float = side / float(count)
	for row in range(count):
		for col in range(count):
			var rect := Rect2(origin + Vector2(col, row) * cell_size + Vector2.ONE * 3, Vector2.ONE * (cell_size - 6))
			var occupied: bool = _snapshot.occupied[row][col] == 1
			draw_style_box(_tile_style(Color("63d4bd") if occupied else Color("26394c")), rect)
	var preview_color := Color("9ce6cb") if _preview.get("valid", false) else Color("ef858b")
	preview_color.a = 0.72
	for coordinate: Array in _preview.get("cells", []):
		var row: int = int(coordinate[0])
		var col: int = int(coordinate[1])
		if row >= 0 and col >= 0 and row < count and col < count:
			var rect := Rect2(origin + Vector2(col, row) * cell_size + Vector2.ONE * 3, Vector2.ONE * (cell_size - 6))
			draw_style_box(_tile_style(preview_color), rect)


static func _tile_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	return style
