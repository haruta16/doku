## 排行列表装配器：协调虚拟列表、浮动玩家行和跟随位置，支持暂停与恢复同步。
class_name RankListViewImpl
extends RefCounted

var _rank_infos: Array[RankInfo] = []
var _my_rank_info: RankInfo = null
var _list_parent: Control = null
var _float_parent: Control = null
var _scroll: ScrollContainer = null
var _create_cell: Callable = Callable()
var _update_cell: Callable = Callable()
var _podium_count: int = 0
var _float_inset_top: float = 0.0
var _float_inset_bottom: float = 0.0

var _cells: Array[Control] = []
var _float_cell: Control = null
var _follow_target: Control = null
var _vsb: VScrollBar = null
var _drag_helper: Node = null
var _sync_paused: bool = false
var _float_at_top: bool = false
var _float_at_bottom: bool = false
var _scroll_orig_offset_top: float = 0.0
var _scroll_orig_offset_bottom: float = 0.0


func setup(config: Dictionary) -> void:
	teardown()
	_rank_infos.assign(config.get("rank_infos", []))
	_my_rank_info = config.get("my_rank_info", null)
	_list_parent = config.get("list_parent", null)
	_float_parent = config.get("float_parent", null)
	_scroll = config.get("scroll", null)
	_create_cell = config.get("create_cell", Callable())
	_update_cell = config.get("update_cell", Callable())
	_podium_count = maxi(0, int(config.get("podium_count", 0)))
	_float_inset_top = float(config.get("float_inset_top", 0.0))
	_float_inset_bottom = float(config.get("float_inset_bottom", 0.0))
	if _scroll != null:
		_scroll_orig_offset_top = _scroll.offset_top
		_scroll_orig_offset_bottom = _scroll.offset_bottom
	if not _create_cell.is_valid() or _list_parent == null or _float_parent == null:
		push_error("RankListViewImpl.setup: 缺 create_cell / list_parent / float_parent")
		return

	_build_cells()
	_hook_scroll()

	if _list_parent.is_inside_tree():
		_list_parent.get_tree().process_frame.connect(sync, CONNECT_ONE_SHOT)
	else:
		sync()


func attach_existing(config: Dictionary) -> void:
	teardown()
	_float_cell = config.get("float_cell", null)
	_follow_target = config.get("follow_target", null)
	_scroll = config.get("scroll", null)
	_float_inset_top = float(config.get("float_inset_top", 0.0))
	_float_inset_bottom = float(config.get("float_inset_bottom", 0.0))
	_podium_count = 0
	if _float_cell == null or _scroll == null:
		push_error("RankListViewImpl.attach_existing: 缺 float_cell / scroll")
		return
	_scroll_orig_offset_top = _scroll.offset_top
	_scroll_orig_offset_bottom = _scroll.offset_bottom
	_float_cell.visible = true
	_hook_scroll()
	if _float_cell.is_inside_tree():
		_float_cell.get_tree().process_frame.connect(sync, CONNECT_ONE_SHOT)
	else:
		sync()


func refresh(rank_infos: Array, my_rank_info: RankInfo) -> void:
	_my_rank_info = my_rank_info
	_rank_infos.assign(rank_infos)

	var list_infos: Array[RankInfo] = []
	for info: RankInfo in _rank_infos:
		if not _is_podium(info):
			list_infos.append(info)
	if list_infos.size() != _cells.size():
		_build_cells()
		sync()
		return
	_follow_target = null
	for i in _cells.size():
		var info: RankInfo = list_infos[i]
		if _update_cell.is_valid():
			_update_cell.call(info, _cells[i])
		if info != null and info.is_self():
			_follow_target = _cells[i]
	if _float_cell != null and _update_cell.is_valid() and _my_rank_info != null:
		_update_cell.call(_my_rank_info, _float_cell)
	_update_float_visibility()
	sync()


func pause_sync() -> void:
	_sync_paused = true


func resume_sync() -> void:
	_sync_paused = false
	sync()


func get_float_cell() -> Control:
	return _float_cell


func get_follow_target() -> Control:
	return _follow_target


func is_float_at_edge() -> bool:
	return _float_at_top or _float_at_bottom


func is_float_at_bottom() -> bool:
	return _float_at_bottom


func is_float_at_top() -> bool:
	return _float_at_top


func sync() -> void:
	if _sync_paused:
		return
	if (
		_float_cell == null
		or not _float_cell.visible
		or _scroll == null
		or not _scroll.is_inside_tree()
	):
		return

	var scroll_parent := _scroll.get_parent() as Control
	var base_top: float = scroll_parent.global_position.y + _scroll_orig_offset_top
	var base_bottom: float = (
		scroll_parent.global_position.y + scroll_parent.size.y + _scroll_orig_offset_bottom
	)
	var row_h: float = _float_cell.size.y
	var lo: float = base_top
	var hi: float = base_bottom - row_h
	var target_y: float
	var at_top := false
	var at_bottom := false
	if _follow_target != null and _follow_target.is_inside_tree():
		var real_y: float = _follow_target.global_position.y
		target_y = clampf(real_y, lo, hi)
		at_top = real_y < lo
		at_bottom = real_y > hi
	else:
		target_y = hi
		at_bottom = true
	_float_at_top = at_top
	_float_at_bottom = at_bottom
	_float_cell.global_position = Vector2(_float_cell.global_position.x, target_y)

	var want_top: float = _scroll_orig_offset_top + (_float_inset_top if at_top else 0.0)
	var want_bottom: float = (
		_scroll_orig_offset_bottom - (_float_inset_bottom if at_bottom else 0.0)
	)
	if not is_equal_approx(_scroll.offset_top, want_top):
		var top_delta: float = want_top - _scroll.offset_top
		_scroll.offset_top = want_top
		_sync_paused = true
		_scroll.scroll_vertical = int(roundf(float(_scroll.scroll_vertical) + top_delta))
		_sync_paused = false
	if not is_equal_approx(_scroll.offset_bottom, want_bottom):
		_scroll.offset_bottom = want_bottom


func teardown() -> void:
	if _scroll != null:
		_scroll.offset_top = _scroll_orig_offset_top
		_scroll.offset_bottom = _scroll_orig_offset_bottom
	if _vsb != null and _vsb.value_changed.is_connected(_on_scrolled):
		_vsb.value_changed.disconnect(_on_scrolled)
	_vsb = null
	if (
		_drag_helper != null
		and is_instance_valid(_drag_helper)
		and _drag_helper.has_signal(&"content_shifted")
		and _drag_helper.content_shifted.is_connected(sync)
	):
		_drag_helper.content_shifted.disconnect(sync)
	_drag_helper = null
	_cells.clear()
	_float_cell = null
	_follow_target = null


func _build_cells() -> void:
	_cells.clear()
	_follow_target = null
	for info: RankInfo in _rank_infos:
		if _is_podium(info):
			continue
		var cell: Control = _create_cell.call(info, _list_parent)
		if cell == null:
			continue
		_cells.append(cell)
		if info != null and info.is_self():
			_follow_target = cell
	if _float_cell == null and _my_rank_info != null:
		_float_cell = _create_cell.call(_my_rank_info, _float_parent)
	_update_float_visibility()


func _is_podium(info: RankInfo) -> bool:
	return info != null and info.rank >= 1 and info.rank <= _podium_count


func _update_float_visibility() -> void:
	if _float_cell != null:
		_float_cell.visible = not _is_podium(_my_rank_info)


func _hook_scroll() -> void:
	if _scroll == null:
		return
	_vsb = _scroll.get_v_scroll_bar()
	if _vsb != null and not _vsb.value_changed.is_connected(_on_scrolled):
		_vsb.value_changed.connect(_on_scrolled)

	_drag_helper = _scroll.get_node_or_null(^"_ScrollDragHelper")
	if (
		_drag_helper != null
		and _drag_helper.has_signal(&"content_shifted")
		and not _drag_helper.content_shifted.is_connected(sync)
	):
		_drag_helper.content_shifted.connect(sync)


func _on_scrolled(_value: float) -> void:
	sync()
