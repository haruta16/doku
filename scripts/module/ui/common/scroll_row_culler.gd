## 滚动行裁剪器：按可视区域更新行显示，减少屏外内容的绘制负担。
class_name ScrollRowCuller
extends RefCounted

var _scroll: ScrollContainer = null
var _row_parent: Control = null
var _culled: Dictionary = {}


func attach(scroll: ScrollContainer, row_parent: Control) -> void:
	detach()
	_scroll = scroll
	_row_parent = row_parent
	RenderingServer.frame_pre_draw.connect(update)


func detach() -> void:
	if RenderingServer.frame_pre_draw.is_connected(update):
		RenderingServer.frame_pre_draw.disconnect(update)
	for id: int in _culled:
		var row: Control = instance_from_id(id) as Control
		if row != null and is_instance_valid(row) and row.is_inside_tree():
			RenderingServer.canvas_item_set_visible(row.get_canvas_item(), row.visible)
	_culled.clear()
	_scroll = null
	_row_parent = null


func get_culled_count() -> int:
	return _culled.size()


func update() -> void:
	if (
		_scroll == null
		or _row_parent == null
		or not is_instance_valid(_scroll)
		or not is_instance_valid(_row_parent)
	):
		return
	if not _scroll.is_visible_in_tree():
		return
	var view: Rect2 = _scroll.get_global_rect()
	var culled: Dictionary = {}
	for child: Node in _row_parent.get_children():
		var row: Control = child as Control
		if row == null:
			continue
		var id: int = row.get_instance_id()
		if row.visible and not view.intersects(_row_bounds(row), true):
			culled[id] = true
			RenderingServer.canvas_item_set_visible(row.get_canvas_item(), false)
		elif _culled.has(id):
			RenderingServer.canvas_item_set_visible(row.get_canvas_item(), row.visible)
	_culled = culled


func _row_bounds(row: Control) -> Rect2:
	var rect: Rect2 = row.get_global_rect()
	for child: Node in row.get_children():
		var c: Control = child as Control
		if c != null and c.visible:
			rect = rect.merge(c.get_global_rect())
	return rect
