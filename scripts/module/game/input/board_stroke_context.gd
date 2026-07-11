class_name BoardStrokeContext
extends RefCounted

var start_cell: Vector2i = Vector2i(-1, -1)
var last_cell: Vector2i = Vector2i(-1, -1)
var target_state: int = 0
var target_pending: bool = false
var had_move: bool = false
var changed: bool = false
var wants_double_tap_window: bool = false


func reset() -> void:
	start_cell = Vector2i(-1, -1)
	last_cell = Vector2i(-1, -1)
	target_state = 0
	target_pending = false
	had_move = false
	changed = false
	wants_double_tap_window = false


func is_active() -> bool:
	return start_cell != Vector2i(-1, -1)
