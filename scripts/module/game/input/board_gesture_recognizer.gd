class_name BoardGestureRecognizer
extends RefCounted

var board: BoardView
var active_scheme: BoardInputScheme
var _stroke := BoardStrokeContext.new()
var _last_tap_cell: Vector2i = Vector2i(-1, -1)


func _init(p_board: BoardView) -> void:
	board = p_board


func on_drag_start(pos: Vector2) -> Array[CellAction]:
	var cell: Vector2i = _resolve_cell(pos)
	var r: int = cell.y
	var c: int = cell.x

	if _last_tap_cell == Vector2i(r, c):
		_last_tap_cell = Vector2i(-1, -1)
		_stroke.reset()
		return active_scheme.double_tap_op.on_double_tap(r, c)

	_stroke.reset()
	_stroke.start_cell = Vector2i(r, c)
	_stroke.last_cell = Vector2i(r, c)
	var actions: Array[CellAction] = active_scheme.tap_op.on_tap(r, c, _stroke)

	if not actions.is_empty():
		_open_double_tap_window(r, c)
	return actions


func on_drag_over(pos: Vector2) -> Array[CellAction]:
	var out: Array[CellAction] = []
	if not _stroke.is_active():
		return out
	var cell: Vector2i = _resolve_cell(pos)
	if cell.x < 0:
		return out
	var r: int = cell.y
	var c: int = cell.x
	if Vector2i(r, c) == _stroke.last_cell:
		return out

	var last: Vector2i = _stroke.last_cell
	var dr: int = r - last.x
	var dc: int = c - last.y
	var steps: int = maxi(absi(dr), absi(dc))
	for i in range(1, steps):
		var ir: int = last.x + int(roundi(float(dr) * i / steps))
		var ic: int = last.y + int(roundi(float(dc) * i / steps))
		var mid: CellAction = active_scheme.swipe_op.on_paint(ir, ic, _stroke, false)
		if mid != null:
			out.append(mid)
	_stroke.last_cell = Vector2i(r, c)
	_stroke.had_move = true
	var cur: CellAction = active_scheme.swipe_op.on_paint(r, c, _stroke, true)
	if cur != null:
		out.append(cur)
	return out


func on_drag_end() -> void:
	active_scheme.swipe_op.on_end(_stroke)
	_stroke.reset()


func reset_for_scheme_switch() -> void:
	_last_tap_cell = Vector2i(-1, -1)
	_stroke.reset()


func _resolve_cell(pos: Vector2) -> Vector2i:
	return board.pointer_to_cell(pos.x, pos.y)


func _open_double_tap_window(r: int, c: int) -> void:
	_last_tap_cell = Vector2i(r, c)
	board.get_tree().create_timer(0.35).timeout.connect(
		func() -> void:
			if _last_tap_cell == Vector2i(r, c):
				_last_tap_cell = Vector2i(-1, -1)
	)
