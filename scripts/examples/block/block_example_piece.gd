## 单块托盘只负责展示与拖拽数据，碰撞合法性由规则模块判断。
extends Control

var shape: Array = []
var enabled: bool = true
var round_id: String = ""
var sequence: int = -1


func show_shape(value: Array, can_drag: bool, identity: String, next_sequence: int) -> void:
	shape = value.duplicate(true)
	enabled = can_drag
	round_id = identity
	sequence = next_sequence
	queue_redraw()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not enabled or shape.is_empty():
		return null
	var preview := Control.new()
	for offset: Array in shape:
		var cell := ColorRect.new()
		cell.color = Color("a1efda")
		cell.position = Vector2(int(offset[1]), int(offset[0])) * 30.0
		cell.size = Vector2(26, 26)
		preview.add_child(cell)
	set_drag_preview(preview)
	return {"kind": "block_piece", "round_id": round_id, "sequence": sequence}


func _draw() -> void:
	if shape.is_empty():
		return
	var extent := Vector2i.ONE
	for offset: Array in shape:
		extent.x = maxi(extent.x, int(offset[1]) + 1)
		extent.y = maxi(extent.y, int(offset[0]) + 1)
	var cell_size: float = minf(34.0, minf(size.x / float(extent.x), size.y / float(extent.y)))
	var origin: Vector2 = (size - Vector2(extent) * cell_size) * 0.5
	for offset: Array in shape:
		var rect := Rect2(origin + Vector2(int(offset[1]), int(offset[0])) * cell_size + Vector2.ONE * 2, Vector2.ONE * (cell_size - 4))
		draw_rect(rect, Color("a1efda") if enabled else Color("60748a"))
