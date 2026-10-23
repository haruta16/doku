## 虚拟列表：只维护可见区及预留范围内的单元，复用节点并保留滚动锚点。
class_name VirtualList
extends Control

enum HeightMode { UNIFORM, PRECOMPUTED }
enum Alignment { START, CENTER, END }

signal layout_updated
signal visible_range_changed
signal viewport_updated
signal update_failed(operation: StringName, message: String)

@export var scroll: ScrollContainer = null
@export var content: Control = null
@export var height_mode: HeightMode = HeightMode.UNIFORM:
	set(value):
		height_mode = value
		_mark_geometry_dirty()
@export var item_height: float = 100.0:
	set(value):
		item_height = value
		_mark_geometry_dirty()
@export var spacing: float = 0.0:
	set(value):
		spacing = value
		_mark_geometry_dirty()
@export var padding_left: float = 0.0:
	set(value):
		padding_left = value
		_mark_geometry_dirty()
@export var padding_right: float = 0.0:
	set(value):
		padding_right = value
		_mark_geometry_dirty()
@export var padding_top: float = 0.0:
	set(value):
		padding_top = value
		_mark_geometry_dirty()
@export var padding_bottom: float = 0.0:
	set(value):
		padding_bottom = value
		_mark_geometry_dirty()
@export var overscan_before: int = 1
@export var overscan_after: int = 1
@export var max_idle_per_scene: int = 2
@export var max_idle_total: int = 8
@export var with_inertia: bool = false:
	set(value):
		with_inertia = value
		if is_instance_valid(_helper):
			_helper.with_inertia = value
@export var elastic_max_overscroll: float = 120.0:
	set(value):
		elastic_max_overscroll = value
		if is_instance_valid(_helper):
			_helper.elastic_max_overscroll = value

var _adapter: VirtualListAdapter = null
var _layout := VirtualListLayout.new()
var _items: Array[Dictionary] = []
var _indices: Dictionary = {}
var _active: Dictionary = {}
var _idle: Array[VirtualListCellState] = []
var _helper: ScrollDragHelper = null
var _requested_active: bool = true
var _effective_active: bool = false
var _layout_ready: bool = false
var _geometry_dirty: bool = true
var _waiting_sort: bool = false
var _updating: bool = false
var _lifecycle_depth: int = 0
var _queued: bool = false
var _exiting: bool = false
var _generation: int = 0
var _display_cycle: int = 0
var _transaction: int = 0
var _pending_position: Dictionary = {}
var _pending_anchor: Dictionary = {}
var _pending_requests: Array[Dictionary] = []
var _pending_viewport_offsets: Dictionary = {}
var _syncing_viewport: bool = false
var _viewport_scroll_remainder: float = 0.0
var _forced: Dictionary = {}
var _bottom_inset: float = 0.0
var _width: float = -1.0
var _visible_signature: Array = []
var _layout_signal_pending: bool = false
var _diagnostics: Dictionary = {
	"instantiate": 0,
	"bind": 0,
	"reset": 0,
	"dirty_reset": 0,
	"layout_rebuild": 0,
	"update": 0,
	"update_usec": 0
}


func _ready() -> void:
	if scroll == null or content == null or content.get_parent() != scroll:
		_fail(&"initialize", "scene requires Scroll and its direct Content Control")
		return
	_helper = ScrollDragHelper.attach(scroll, with_inertia)
	_helper.elastic_max_overscroll = elastic_max_overscroll
	set_notify_transform(true)
	_helper.content_shifted.connect(_on_content_shifted)
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	scroll.resized.connect(_on_resized)
	content.resized.connect(_on_content_resized)
	scroll.sort_children.connect(_on_sorted)
	visibility_changed.connect(_on_visibility_changed)
	item_rect_changed.connect(_on_transform_changed)
	scroll.theme_changed.connect(_on_resized)
	_effective_active = _requested_active and is_visible_in_tree()
	_queue_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_queue_update()


## 使当前显示周期失效，清理待处理请求并释放单元格，避免旧异步回调复用新状态。
func _exit_tree() -> void:
	_exiting = true
	_viewport_scroll_remainder = 0.0
	_display_cycle += 1
	_pending_position.clear()
	_pending_viewport_offsets.clear()
	_pending_requests.clear()
	_release_all(true)
	if is_instance_valid(_helper) and _helper.content_shifted.is_connected(_on_content_shifted):
		_helper.content_shifted.disconnect(_on_content_shifted)
	if is_instance_valid(scroll):
		var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
		if scrollbar.value_changed.is_connected(_on_scroll_changed):
			scrollbar.value_changed.disconnect(_on_scroll_changed)
		if scroll.resized.is_connected(_on_resized):
			scroll.resized.disconnect(_on_resized)
		if scroll.sort_children.is_connected(_on_sorted):
			scroll.sort_children.disconnect(_on_sorted)
		if scroll.theme_changed.is_connected(_on_resized):
			scroll.theme_changed.disconnect(_on_resized)
	if is_instance_valid(content) and content.resized.is_connected(_on_content_resized):
		content.resized.disconnect(_on_content_resized)


## 布局或生命周期回调中切换数据源会先排队；正式切换时清空缓存和滚动状态再重建。
func set_adapter(adapter: VirtualListAdapter) -> void:
	if _updating or _lifecycle_depth > 0:
		_pending_requests.append({"operation": &"adapter", "adapter": adapter})
		_queue_update()
		return
	if _adapter == adapter:
		return
	_display_cycle += 1
	_pending_position.clear()
	_pending_viewport_offsets.clear()
	_pending_requests.clear()
	_viewport_scroll_remainder = 0.0
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_release_all(true)
	_adapter = adapter
	_items.clear()
	_indices.clear()
	_layout_ready = false
	_geometry_dirty = true
	_width = -1.0
	if adapter != null:
		reload(false)
	else:
		_queue_update()


## 先校验全部条目的稳定键、场景和几何数据，全部通过才提交；可保留当前滚动锚点。
func reload(preserve_anchor: bool = true) -> bool:
	if _adapter == null:
		return _fail(&"reload", "adapter is missing")
	if _updating or _lifecycle_depth > 0:
		_pending_requests.append({"operation": &"reload", "preserve": preserve_anchor})
		_queue_update()
		return true
	var candidate: Array[Dictionary] = []
	var candidate_indices: Dictionary = {}
	var count: int = _adapter.get_item_count()
	if count < 0:
		return _fail(&"reload", "item count must be nonnegative")
	var available_width: float = maxf(0.0, _content_width() - padding_left - padding_right)
	for index: int in count:
		var key: String = _adapter.get_item_key(index)
		var scene: PackedScene = _adapter.get_item_scene(index)
		if key.is_empty() or candidate_indices.has(key):
			return _fail(&"reload", "item keys must be nonempty and unique")
		if not _valid_scene(scene):
			return _fail(&"reload", "item scene must have an instantiable Control root")
		var height: float = item_height
		if height_mode == HeightMode.PRECOMPUTED:
			height = _adapter.get_item_height(index, available_width)
		if not is_finite(height) or height <= 0.0:
			return _fail(&"reload", "item height must be positive and finite")
		candidate.append(
			{
				"key": key,
				"scene": scene,
				"height": height,
				"revision": _adapter.get_item_revision(index),
				"data": _adapter.get_item_data(index)
			}
		)
		candidate_indices[key] = index
	var geometry: VirtualListLayout = _prepare_layout(candidate, _content_width())
	if geometry == null:
		return _fail(&"reload", "invalid geometry configuration")
	_begin_geometry_change(preserve_anchor)
	_items = candidate
	_indices = candidate_indices
	_layout = geometry
	_geometry_dirty = false
	_commit_geometry()
	return true


func refresh_presentation() -> void:
	if _updating or _lifecycle_depth > 0:
		_queue_update()
		return
	_update_now()


## 更新单项数据与可选高度；条目数量或稳定键变化属于结构调整，需要重新加载。
func refresh_item(index: int, geometry_changed: bool = false) -> bool:
	if not has_item(index) or _adapter == null:
		return _fail(&"refresh_item", "item index is out of range")
	if _updating or _lifecycle_depth > 0:
		_pending_requests.append(
			{"operation": &"refresh", "index": index, "geometry": geometry_changed}
		)
		_queue_update()
		return true
	if _adapter.get_item_count() != _items.size():
		return _fail(&"refresh_item", "structural changes require reload")
	for item_index: int in _items.size():
		if _adapter.get_item_key(item_index) != _items[item_index].key:
			return _fail(&"refresh_item", "structural changes require reload")
	var scene: PackedScene = _adapter.get_item_scene(index)
	if not _valid_scene(scene):
		return _fail(&"refresh_item", "item scene must have an instantiable Control root")
	var candidate: Array[Dictionary] = _items.duplicate()
	var descriptor: Dictionary = _items[index].duplicate()
	descriptor.scene = scene
	descriptor.data = _adapter.get_item_data(index)
	descriptor.revision = _adapter.get_item_revision(index)
	if geometry_changed and height_mode == HeightMode.PRECOMPUTED:
		descriptor.height = _adapter.get_item_height(
			index, maxf(0.0, _content_width() - padding_left - padding_right)
		)
		if not is_finite(descriptor.height) or descriptor.height <= 0.0:
			return _fail(&"refresh_item", "item height must be positive and finite")
	candidate[index] = descriptor
	var geometry: VirtualListLayout = null
	if geometry_changed:
		geometry = _prepare_layout(candidate, _content_width())
		if geometry == null:
			return _fail(&"refresh_item", "invalid geometry configuration")
		_begin_geometry_change(true)
	_items = candidate
	_forced[index] = true
	if geometry_changed:
		_layout = geometry
		_geometry_dirty = false
		_commit_geometry()
	else:
		_update_now()
	return true


## 把索引转换为稳定键保存滚动请求，停止惯性后由可见区更新流程定位。
func scroll_to_index(index: int, alignment: Alignment = Alignment.START) -> bool:
	if not has_item(index) or alignment < Alignment.START or alignment > Alignment.END:
		return _fail(&"scroll_to_index", "invalid index or alignment")
	_pending_position = {"key": _items[index].key, "alignment": alignment}
	_viewport_scroll_remainder = 0.0
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_update_now()
	return true


func scroll_to_offset(offset: float) -> bool:
	if not is_finite(offset):
		return _fail(&"scroll_to_offset", "offset must be finite")
	_pending_position = {"offset": offset}
	_viewport_scroll_remainder = 0.0
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_update_now()
	return true


func set_viewport_offsets(top: float, bottom: float) -> bool:
	if not is_finite(top) or not is_finite(bottom):
		return _fail(&"set_viewport_offsets", "offsets must be finite")
	if _exiting:
		return _fail(&"set_viewport_offsets", "list is exiting")
	var pending: Dictionary = {"top": top, "bottom": bottom}
	if _pending_viewport_offsets.has("origin_top"):
		pending.origin_top = _pending_viewport_offsets.origin_top
	_pending_viewport_offsets = pending
	if (
		_updating
		or _lifecycle_depth > 0
		or not _effective_active
		or not _layout_ready
		or _waiting_sort
		or _geometry_dirty
	):
		_queue_update()
	else:
		_update_now()
	return true


func has_item(index: int) -> bool:
	return index >= 0 and index < _items.size()


func find_item_index(key: String) -> int:
	return _indices.get(key, -1)


func get_item_rect(index: int) -> Rect2:
	if not has_item(index):
		_fail(&"get_item_rect", "item index is out of range")
		return Rect2()
	return _layout.get_item_rect(index) if _layout_ready else Rect2()


func get_item_rect_in_viewport(index: int) -> Rect2:
	var rect: Rect2 = get_item_rect(index)
	if rect == Rect2() or not is_instance_valid(content):
		return Rect2()
	return content.get_global_transform_with_canvas() * rect


func get_visible_bindings() -> Array[VirtualListBinding]:
	var result: Array[VirtualListBinding] = []
	if not _effective_active or not _layout_ready:
		return result
	var interval: Vector2 = _visible_interval()
	var visible: Vector2i = _layout.get_visible_range(interval.x, interval.y)
	if visible == VirtualListLayout.EMPTY_RANGE:
		return result
	for index: int in range(visible.x, visible.y):
		var state: VirtualListCellState = _active.get(index)
		if state != null and is_binding_current(state.binding):
			result.append(state.binding)
	return result


func is_binding_current(binding: VirtualListBinding) -> bool:
	if (
		binding == null
		or not binding.is_valid()
		or not _effective_active
		or _exiting
		or not _layout_ready
		or not has_item(binding.index)
	):
		return false
	var state: VirtualListCellState = _active.get(binding.index)
	return (
		state != null
		and state.phase == VirtualListCellState.Phase.ACTIVE
		and state.binding == binding
		and state.display_cycle == _display_cycle
		and state.binding.generation == binding.generation
		and _items[binding.index].key == binding.key
	)


func set_active(active: bool) -> void:
	if not active:
		_pending_position.clear()
		_pending_viewport_offsets.clear()
		_pending_requests.clear()
	_requested_active = active
	_sync_activity()


func get_diagnostics() -> Dictionary:
	var result: Dictionary = _diagnostics.duplicate()
	result.active = _active.size()
	result.idle = _idle.size()
	return result


func get_scroll_offset() -> float:
	return float(scroll.scroll_vertical) if is_instance_valid(scroll) else 0.0


func get_content_bottom_inset() -> float:
	return _bottom_inset


func set_content_bottom_inset(value: float) -> bool:
	if not is_finite(value) or value < 0.0:
		return _fail(&"set_content_bottom_inset", "inset must be finite and nonnegative")
	if _bottom_inset != value:
		_bottom_inset = value
		_mark_geometry_dirty()
	return true


func get_clip_rect_in_viewport() -> Rect2:
	if not is_instance_valid(scroll) or not is_inside_tree():
		return Rect2()
	var rect: Rect2 = scroll.get_global_transform_with_canvas() * _scroll_clip_rect()
	var ancestor: Node = scroll.get_parent()
	while ancestor != null:
		if ancestor is Control:
			var control: Control = ancestor as Control
			if control.clip_contents:
				rect = rect.intersection(
					control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
				)
		ancestor = ancestor.get_parent()
	return rect.intersection(get_viewport().get_visible_rect())


func _valid_scene(scene: PackedScene) -> bool:
	if scene == null or not scene.can_instantiate():
		return false
	var state: SceneState = scene.get_state()
	return (
		state.get_node_count() > 0 and ClassDB.is_parent_class(state.get_node_type(0), &"Control")
	)


func _prepare_layout(items: Array[Dictionary], width: float) -> VirtualListLayout:
	var heights := PackedFloat64Array()
	if height_mode == HeightMode.PRECOMPUTED:
		for descriptor: Dictionary in items:
			heights.append(descriptor.height)
	var layout := VirtualListLayout.new()
	var geometry_width: float = maxf(width, padding_left + padding_right) if width <= 0.0 else width
	if not layout.configure(
		items.size(),
		geometry_width,
		heights,
		item_height,
		spacing,
		Vector4(padding_left, padding_top, padding_right, padding_bottom + _bottom_inset)
	):
		return null
	return layout


func _begin_geometry_change(preserve_anchor: bool) -> void:
	_viewport_scroll_remainder = 0.0
	if _pending_anchor.is_empty() and _layout_ready:
		if preserve_anchor and not _items.is_empty():
			var interval: Vector2 = _visible_interval()
			var index: int = _layout.find_anchor_index(interval.x)
			_pending_anchor = {
				"key": _items[index].key,
				"index": index,
				"offset": _layout.get_item_rect(index).position.y - interval.x
			}
		else:
			_pending_anchor = {"scroll": get_scroll_offset()}
	_waiting_sort = true
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_transaction += 1


func _commit_geometry() -> void:
	_diagnostics.layout_rebuild += 1
	_layout_signal_pending = true
	_layout_ready = false
	_width = _content_width()
	if (
		not is_node_ready()
		or not is_instance_valid(content)
		or _width <= padding_left + padding_right
		or _scroll_clip_rect().size.y <= 0.0
	):
		_waiting_sort = false
		_queue_update()
		return
	content.custom_minimum_size = Vector2(_width, _layout.get_total_height())

	scroll.get_minimum_size()
	if _pending_viewport_offsets.has("origin_top"):
		_syncing_viewport = true
		scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
		_syncing_viewport = false
	_waiting_sort = true
	scroll.queue_sort()


func _mark_geometry_dirty() -> void:
	_geometry_dirty = true
	_queue_update()


func _queue_update() -> void:
	if _queued or _exiting:
		return
	_queued = true
	_flush.call_deferred()


func _flush() -> void:
	_queued = false
	if _exiting or not is_node_ready() or scroll == null or content == null:
		return
	if _updating:
		_queue_update()
		return
	var requests: Array[Dictionary] = _pending_requests
	_pending_requests = []
	for request: Dictionary in requests:
		match request.operation:
			&"adapter":
				set_adapter(request.adapter)
			&"reload":
				reload(request.preserve)
			&"refresh":
				refresh_item(request.index, request.geometry)
	if (
		_layout_ready
		and not _waiting_sort
		and not _geometry_dirty
		and _effective_active
		and not _pending_viewport_offsets.is_empty()
	):
		_update_now()
	elif not _layout_ready and _effective_active and not _pending_viewport_offsets.is_empty():
		if not _pending_viewport_offsets.has("origin_top"):
			_pending_viewport_offsets.origin_top = offset_top
		_syncing_viewport = true
		offset_top = _pending_viewport_offsets.top
		offset_bottom = _pending_viewport_offsets.bottom
		_syncing_viewport = false
	var width: float = _content_width()
	if width <= padding_left + padding_right or _scroll_clip_rect().size.y <= 0.0:
		return
	if _geometry_dirty or not is_equal_approx(width, _width):
		var candidate: Array[Dictionary] = _items.duplicate()
		if height_mode == HeightMode.PRECOMPUTED and _adapter != null:
			var refreshed: Dictionary = _prepare_width_snapshot(width)
			if not refreshed.is_empty():
				candidate = refreshed.items
		var geometry: VirtualListLayout = _prepare_layout(candidate, width)
		_geometry_dirty = false
		if geometry == null:
			_fail(&"layout", "invalid geometry configuration")
			return
		_begin_geometry_change(true)
		_items = candidate
		_layout = geometry
		_commit_geometry()
		return
	if _waiting_sort:
		return
	if not _layout_ready:
		_commit_geometry()
		return
	_update_now()


func _prepare_width_snapshot(width: float) -> Dictionary:
	if _adapter.get_item_count() != _items.size():
		return {}
	var candidate: Array[Dictionary] = []
	for index: int in _items.size():
		if _adapter.get_item_key(index) != _items[index].key:
			return {}
		var scene: PackedScene = _adapter.get_item_scene(index)
		var height: float = _adapter.get_item_height(index, width - padding_left - padding_right)
		if not _valid_scene(scene) or not is_finite(height) or height <= 0.0:
			_fail(&"layout", "width candidate contains invalid scene or height")
			return {}
		candidate.append(
			{
				"key": _items[index].key,
				"scene": scene,
				"height": height,
				"revision": _adapter.get_item_revision(index),
				"data": _adapter.get_item_data(index)
			}
		)
	if _prepare_layout(candidate, width) == null:
		_fail(&"layout", "width candidate contains invalid geometry")
		return {}
	return {"items": candidate}


func _on_sorted() -> void:
	if _layout_ready and not _waiting_sort and is_instance_valid(_helper):
		_helper.synchronize_content_position()
	_complete_sort.call_deferred(_transaction)


func _complete_sort(transaction: int) -> void:
	if _exiting or transaction != _transaction or not _waiting_sort:
		return
	_waiting_sort = false
	_layout_ready = true
	_update_now()


func _update_now() -> void:
	if _exiting or _updating:
		return
	if _lifecycle_depth > 0:
		_queue_update()
		return
	if not _layout_ready or _waiting_sort or _geometry_dirty:
		if _geometry_dirty:
			_queue_update()
		return
	_updating = true
	var started: int = Time.get_ticks_usec()
	if _effective_active:
		_apply_position()
		_apply_viewport_offsets()
		_update_cells()
	_diagnostics.update += 1
	_diagnostics.update_usec = Time.get_ticks_usec() - started
	if _layout_signal_pending:
		_layout_signal_pending = false
		layout_updated.emit()
	var signature: Array = []
	var bindings: Array[VirtualListBinding] = get_visible_bindings()
	for binding: VirtualListBinding in bindings:
		signature.append([binding.key, binding.index])
	if signature != _visible_signature:
		_visible_signature = signature
		visible_range_changed.emit()
	if _effective_active:
		viewport_updated.emit()
	_updating = false
	if (
		not _pending_requests.is_empty()
		or (
			_effective_active
			and (not _pending_position.is_empty() or not _pending_viewport_offsets.is_empty())
		)
	):
		_queue_update()


func _apply_viewport_offsets() -> void:
	if _pending_viewport_offsets.is_empty():
		return
	var offsets: Dictionary = _pending_viewport_offsets
	_pending_viewport_offsets = {}
	var origin_top: float = offsets.get("origin_top", offset_top)
	var delta: float = offsets.top - origin_top
	if offset_top == offsets.top and offset_bottom == offsets.bottom and delta == 0.0:
		return
	var logical_delta: float = get_transform().affine_inverse().basis_xform(Vector2(0.0, delta)).y
	var target: float = get_scroll_offset() + logical_delta
	if delta != 0.0:
		target += _viewport_scroll_remainder
	_syncing_viewport = true
	offset_top = offsets.top
	offset_bottom = offsets.bottom

	scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	var clamped: float = clampf(target, 0.0, maxf(0.0, scrollbar.max_value - scrollbar.page))
	scroll.scroll_vertical = roundi(clamped)
	if clamped != target:
		_viewport_scroll_remainder = 0.0
	elif delta != 0.0:
		_viewport_scroll_remainder = clamped - get_scroll_offset()
	if is_instance_valid(_helper):
		_helper.synchronize_content_position()
	_syncing_viewport = false


func _apply_position() -> void:
	if _pending_anchor.is_empty() and _pending_position.is_empty() and not _items.is_empty():
		return
	var target: float = get_scroll_offset()
	if _items.is_empty():
		target = 0.0
	if not _pending_anchor.is_empty():
		if _pending_anchor.has("scroll"):
			target = _pending_anchor.scroll
		elif not _items.is_empty():
			var index: int = find_item_index(_pending_anchor.key)
			if index < 0:
				index = mini(_pending_anchor.index, _items.size() - 1)
			var clip: Rect2 = (
				content.get_global_transform_with_canvas().affine_inverse()
				* get_clip_rect_in_viewport()
			)
			var top_inset: float = clip.position.y - get_scroll_offset()
			target = _layout.get_item_rect(index).position.y - _pending_anchor.offset - top_inset
		_pending_anchor.clear()
	if not _pending_position.is_empty():
		if _pending_position.has("offset"):
			target = _pending_position.offset
		else:
			var index: int = find_item_index(_pending_position.key)
			if index < 0:
				_fail(&"scroll_to_index", "pending target key was deleted")
			else:
				var rect: Rect2 = _layout.get_item_rect(index)
				var clip: Rect2 = (
					content.get_global_transform_with_canvas().affine_inverse()
					* get_clip_rect_in_viewport()
				)
				var top_inset: float = clip.position.y - get_scroll_offset()
				target = rect.position.y - top_inset
				if _pending_position.alignment == Alignment.CENTER:
					target -= (clip.size.y - rect.size.y) * 0.5
				elif _pending_position.alignment == Alignment.END:
					target -= clip.size.y - rect.size.y
		_pending_position.clear()
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	target = clampf(target, 0.0, maxf(0.0, scrollbar.max_value - scrollbar.page))
	scroll.scroll_vertical = roundi(target)

	if (
		is_instance_valid(_helper)
		and not is_equal_approx(content.position.y, -float(scroll.scroll_vertical))
	):
		_helper.stop_motion()


func _update_cells() -> void:
	var interval: Vector2 = _visible_interval()
	var range_indices: Vector2i = _layout.get_active_range(
		interval.x, interval.y, maxi(0, overscan_before), maxi(0, overscan_after)
	)
	var recycled: Array[VirtualListCellState] = []
	var cycle: int = _display_cycle
	var active_indices: Array = _active.keys()
	for index: int in active_indices:
		if cycle != _display_cycle or _exiting:
			break
		var state: VirtualListCellState = _active.get(index)
		if state == null:
			continue
		var keep: bool = (
			range_indices != VirtualListLayout.EMPTY_RANGE
			and index >= range_indices.x
			and index < range_indices.y
			and has_item(index)
		)
		if keep:
			var descriptor: Dictionary = _items[index]
			keep = (
				state.binding != null
				and state.binding.key == descriptor.key
				and state.scene == descriptor.scene
				and state.binding.revision == descriptor.revision
				and not _forced.has(index)
				and state.binding.is_valid()
			)
		if not keep:
			_active.erase(index)
			_release(state)
			recycled.append(state)
	if range_indices != VirtualListLayout.EMPTY_RANGE:
		for index: int in range(range_indices.x, range_indices.y):
			if not _effective_active or _exiting or cycle != _display_cycle:
				break
			if _active.has(index):
				var retained: VirtualListCellState = _active[index]
				var rect: Rect2 = _layout.get_item_rect(index)
				_apply_cell_rect(retained.cell, rect)
				retained.cell.show()
				if not _present_cell(retained, rect):
					break
				continue
			var descriptor: Dictionary = _items[index]
			var state: VirtualListCellState = _take_cell(descriptor.scene, recycled)
			if state != null:
				_bind(state, index)
	_forced.clear()
	_finalize_recycled(recycled)


func _take_cell(scene: PackedScene, recycled: Array[VirtualListCellState]) -> VirtualListCellState:
	for index: int in recycled.size():
		if recycled[index].scene == scene:
			var state: VirtualListCellState = recycled[index]
			recycled.remove_at(index)
			return state
	for index: int in _idle.size():
		if _idle[index].scene == scene:
			var state: VirtualListCellState = _idle[index]
			_idle.remove_at(index)
			return state
	var owner_adapter: VirtualListAdapter = _adapter
	var cell: Control = owner_adapter.create_cell(scene, content)
	_diagnostics.instantiate += 1
	if not is_instance_valid(cell):
		_fail(&"create_cell", "factory returned invalid cell")
		return null
	var state := VirtualListCellState.new(cell, scene, owner_adapter)
	if (
		cell.is_queued_for_deletion()
		or cell.get_parent() != content
		or cell.visible
		or not VirtualListCellState.factory_is_suppressed(cell)
	):
		state.disable_subtree()
		owner_adapter.reset_cell(cell)
		_dispose(state)
		_fail(&"create_cell", "factory must return hidden disabled cell attached to Content")
		return null
	owner_adapter.initialize_cell(cell)
	if not is_instance_valid(cell) or cell.is_queued_for_deletion() or cell.get_parent() != content:
		_fail(&"initialize_cell", "initialization invalidated cell")
		if is_instance_valid(cell):
			_dispose(state)
		return null
	state.capture_subtree()
	state.disable_subtree()
	return state


func _bind(state: VirtualListCellState, index: int) -> void:
	var cell: Control = state.cell
	var rect: Rect2 = _layout.get_item_rect(index)
	var minimum: Vector2 = cell.get_combined_minimum_size()
	if minimum.x > rect.size.x or minimum.y > rect.size.y:
		_dispose(state)
		_fail(&"bind_cell", "cell minimum size exceeds declared item rectangle")
		return
	state.phase = VirtualListCellState.Phase.BINDING
	state.disable_subtree()
	_apply_cell_rect(cell, rect)
	_generation += 1
	var descriptor: Dictionary = _items[index]
	state.binding = VirtualListBinding.new(
		cell, descriptor.key, index, descriptor.revision, _generation, descriptor.data
	)
	state.display_cycle = _display_cycle
	state.adapter.bind_cell(cell, state.binding)
	_diagnostics.bind += 1
	if (
		not state.binding.is_valid()
		or not is_instance_valid(cell)
		or cell.is_queued_for_deletion()
		or cell.get_parent() != content
		or not _effective_active
		or state.display_cycle != _display_cycle
	):
		_release(state)
		_dispose(state)
		_fail(&"bind_cell", "binding did not complete in current display cycle")
		return
	minimum = cell.get_combined_minimum_size()
	if minimum.x > rect.size.x or minimum.y > rect.size.y:
		_release(state)
		_dispose(state)
		_fail(&"bind_cell", "bound cell minimum size exceeds declared item rectangle")
		return
	state.capture_subtree()
	_apply_cell_rect(cell, rect)
	state.phase = VirtualListCellState.Phase.ACTIVE
	_active[index] = state
	state.restore_subtree()
	cell.show()
	_present_cell(state, rect)


func _present_cell(state: VirtualListCellState, rect: Rect2) -> bool:
	if (
		not _effective_active
		or _exiting
		or state.display_cycle != _display_cycle
		or state.binding == null
		or not is_binding_current(state.binding)
	):
		return false
	state.adapter.present_cell(state.cell, state.binding, rect)

	return (
		_effective_active
		and not _exiting
		and state.display_cycle == _display_cycle
		and state.binding != null
		and is_binding_current(state.binding)
	)


func _apply_cell_rect(cell: Control, rect: Rect2) -> void:
	cell.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cell.rotation = 0.0
	cell.scale = Vector2.ONE
	cell.position = rect.position
	cell.size = rect.size


func _release(state: VirtualListCellState) -> void:
	if (
		state.phase == VirtualListCellState.Phase.RELEASING
		or state.phase == VirtualListCellState.Phase.DISPOSED
	):
		return
	if state.binding != null:
		state.binding.invalidate()
	state.phase = VirtualListCellState.Phase.RELEASING
	_lifecycle_depth += 1
	if is_instance_valid(state.cell) and not state.cell.is_queued_for_deletion():
		state.capture_subtree()
		if is_instance_valid(_helper):
			_helper.cancel_pressed_interaction(state.cell)
		if state.binding != null:
			state.adapter.unbind_cell(state.cell, state.binding)
		if is_instance_valid(state.cell) and not state.cell.is_queued_for_deletion():
			state.reset_press_scales()
			state.adapter.reset_cell(state.cell)
			_diagnostics.reset += 1
			_report_unquiet_reset(state.cell)
			state.disable_subtree()
	state.binding = null
	state.phase = VirtualListCellState.Phase.IDLE
	_lifecycle_depth -= 1


func _report_unquiet_reset(cell: Control) -> void:
	if OS.has_feature("rel"):
		return
	var players: Array[Node] = cell.find_children("*", "AnimationPlayer", true, false)
	var playing: PackedStringArray = PackedStringArray()
	for node: Node in players:
		var player: AnimationPlayer = node as AnimationPlayer
		if player.is_playing():
			playing.append(str(cell.get_path_to(player)))
	if playing.is_empty():
		return
	_diagnostics.dirty_reset += 1
	push_error(
		(
			"VirtualList: reset_cell: %s left AnimationPlayer playing: %s"
			% [cell.name, ", ".join(playing)]
		)
	)


func _dispose(state: VirtualListCellState) -> void:
	if state.phase == VirtualListCellState.Phase.DISPOSED:
		return
	state.phase = VirtualListCellState.Phase.DISPOSED
	if is_instance_valid(state.cell):
		_lifecycle_depth += 1
		state.adapter.dispose_cell(state.cell)
		_lifecycle_depth -= 1


func _release_all(dispose: bool) -> void:
	var states: Array = _active.values()
	_active.clear()
	var recycled: Array[VirtualListCellState] = []
	if dispose:
		recycled = _idle
		_idle = []
	for state: VirtualListCellState in states:
		_release(state)
		recycled.append(state)
	if dispose:
		for state: VirtualListCellState in recycled:
			_dispose(state)
	else:
		_finalize_recycled(recycled)


func _finalize_recycled(recycled: Array[VirtualListCellState]) -> void:
	for state: VirtualListCellState in recycled:
		if state.phase != VirtualListCellState.Phase.IDLE:
			continue
		if (
			_exiting
			or state.adapter != _adapter
			or not is_instance_valid(state.cell)
			or state.cell.is_queued_for_deletion()
		):
			_dispose(state)
		else:
			_idle.append(state)
	_trim_idle()


func _trim_idle() -> void:
	var counts: Dictionary = {}
	for state: VirtualListCellState in _idle:
		counts[state.scene] = int(counts.get(state.scene, 0)) + 1
	var retained: Array[VirtualListCellState] = []
	var evicted: Array[VirtualListCellState] = []
	var remaining: int = _idle.size()
	for state: VirtualListCellState in _idle:
		if counts[state.scene] > maxi(0, max_idle_per_scene) or remaining > maxi(0, max_idle_total):
			counts[state.scene] -= 1
			remaining -= 1
			evicted.append(state)
		else:
			retained.append(state)
	_idle = retained
	for state: VirtualListCellState in evicted:
		_dispose(state)


func _sync_activity() -> void:
	var effective: bool = _requested_active and is_inside_tree() and is_visible_in_tree()
	if effective == _effective_active:
		return
	_effective_active = effective
	_display_cycle += 1
	if not effective:
		_viewport_scroll_remainder = 0.0
		_pending_position.clear()
		_pending_viewport_offsets.clear()
		_pending_requests.clear()
		if is_instance_valid(_helper):
			_helper.stop_motion()
		_release_all(false)
		_visible_signature.clear()
	else:
		_queue_update()


func _scroll_clip_rect() -> Rect2:
	if not is_instance_valid(scroll):
		return Rect2()
	var panel: StyleBox = scroll.get_theme_stylebox(&"panel")
	var offset := Vector2(panel.get_margin(SIDE_LEFT), panel.get_margin(SIDE_TOP))
	var dimensions: Vector2 = (
		scroll.size - offset - Vector2(panel.get_margin(SIDE_RIGHT), panel.get_margin(SIDE_BOTTOM))
	)
	if scroll.get_v_scroll_bar().visible:
		dimensions.x -= scroll.get_v_scroll_bar().size.x
	if scroll.get_h_scroll_bar().visible:
		dimensions.y -= scroll.get_h_scroll_bar().size.y
	return Rect2(offset, dimensions.max(Vector2.ZERO))


func _content_width() -> float:
	return _scroll_clip_rect().size.x


func _visible_interval() -> Vector2:
	var clip: Rect2 = (
		content.get_global_transform_with_canvas().affine_inverse() * get_clip_rect_in_viewport()
	)
	return Vector2(clip.position.y, clip.end.y)


func _on_content_shifted() -> void:
	_update_now()


func _on_scroll_changed(_value: float) -> void:
	_queue_update()


func _on_resized() -> void:
	if _syncing_viewport:
		return
	if (
		_layout_ready
		and _pending_anchor.is_empty()
		and not is_equal_approx(_content_width(), _width)
	):
		_begin_geometry_change(true)
	_queue_update()


func _on_content_resized() -> void:
	_queue_update()


func _on_transform_changed() -> void:
	_queue_update()


func _on_visibility_changed() -> void:
	_sync_activity()


func _fail(operation: StringName, message: String) -> bool:
	push_error("VirtualList: %s: %s" % [operation, message])
	update_failed.emit(operation, message)
	return false
