## 自身行的边缘悬浮控制器；真实列表项滚出视口时，在上/下边缘显示副本，返回视口后隐藏副本。

class_name RankFloatingRowController
extends RefCounted

var _list: VirtualList = null
var _cell: RankCell = null
var _base_top: float = 20.0
var _base_bottom: float = -18.0
var _base_captured: bool = false
var _syncing: bool = false
var _dirty: bool = false
var _at_top: bool = false
var _at_bottom: bool = false


func setup(list: VirtualList, cell: RankCell) -> void:
	_list = list
	_cell = cell
	if not _base_captured:
		_base_top = list.offset_top
		_base_bottom = list.offset_bottom
		_base_captured = true


func is_at_edge() -> bool:
	return _at_top or _at_bottom


func is_at_top() -> bool:
	return _at_top


func is_at_bottom() -> bool:
	return _at_bottom


## 根据真实自身行的位置判断是否需要边缘副本，并同步顶部或底部浮动展示。
func sync(item_key: String) -> void:
	if _syncing:
		_dirty = true
		return
	if (
		not is_instance_valid(_list)
		or not is_instance_valid(_cell)
		or not _cell.is_visible_in_tree()
	):
		return
	_syncing = true
	var attempts: int = 0
	while attempts < 4:
		_dirty = false
		_sync_once(item_key)
		attempts += 1
		if not _dirty:
			break
	_syncing = false


func _sync_once(item_key: String) -> void:
	var parent: Control = _list.get_parent() as Control
	var base: Rect2 = (
		parent.get_global_transform_with_canvas()
		* Rect2(
			Vector2(_list.position.x, _base_top),
			Vector2(_list.size.x, parent.size.y + _base_bottom - _base_top)
		)
	)
	base = base.intersection(_list.get_viewport().get_visible_rect())
	var ancestor: Node = parent
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			base = base.intersection(
				ancestor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ancestor.size)
			)
		ancestor = ancestor.get_parent()
	if base.size.y <= 0.0:
		return
	var row_height: float = _cell.size.y * _cell.get_global_transform_with_canvas().get_scale().y
	var low: float = base.position.y
	var high: float = maxf(low, base.end.y - row_height)
	var index: int = _list.find_item_index(item_key)
	var real_rect: Rect2 = _list.get_item_rect_in_viewport(index) if index >= 0 else Rect2()
	if index >= 0 and real_rect.size.y <= 0.0:
		return
	var real_y: float = real_rect.position.y if index >= 0 else high + 1.0
	var top: bool = real_y < low - 0.5
	var bottom: bool = real_y > high + 0.5
	var wanted_top: float = _base_top + (15.0 if top else 0.0)
	var wanted_bottom: float = _base_bottom - (15.0 if bottom else 0.0)
	if (
		not is_equal_approx(_list.offset_top, wanted_top)
		or not is_equal_approx(_list.offset_bottom, wanted_bottom)
	):
		_list.set_viewport_offsets(wanted_top, wanted_bottom)
		_dirty = true
	if _dirty:
		return
	_at_top = top
	_at_bottom = bottom
	var position_in_viewport: Vector2 = Vector2(
		base.position.x + 20.0 * parent.get_global_transform_with_canvas().get_scale().x,
		clampf(real_y, low, high)
	)
	_cell.position = (
		(_cell.get_parent() as Control).get_global_transform_with_canvas().affine_inverse()
		* position_in_viewport
	)
	_cell.set_self_shadow(top or bottom, top)


## 断开监听并清理浮动状态，防止页面销毁后继续跟踪列表滚动。
func teardown() -> void:
	if is_instance_valid(_list):
		_list.set_viewport_offsets(_base_top, _base_bottom)
	_list = null
	_cell = null
	_at_top = false
	_at_bottom = false
