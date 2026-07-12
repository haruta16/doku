extends Node

var _registry: Dictionary = {}
var _cache: Dictionary = {}
var _stacks: Dictionary = {}
var _next_z: Dictionary = {}
var events: UIEvents = UIEvents.new()

var _mask: ColorRect = null
var _mask_ref_count: int = 0
var _mask_tween: Tween = null

var _mask_secondary: ColorRect = null
var _mask_secondary_tween: Tween = null

var _tracker_observer: UITrackerObserver = null


func _ready() -> void:
	_registry = UIRegistry.build_registry()
	_tracker_observer = UITrackerObserver.new(events)


func show_ui(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if not _registry.has(ui_name):
		push_error("UIManager: unknown ui '%s'" % ui_name)
		return null
	var win: UIFrameWindow = _get_or_create(ui_name)
	if win == null:
		return null
	if win.is_showing():
		win.on_show(params)
		return win
	var was_closing: bool = win._window_state == UIBaseWindow.WindowState.CLOSING
	if was_closing:
		win._abort_close_animation()
	var layer: int = win.ui_layer
	_assign_z_index(win, layer)
	_apply_safe_area(ui_name, win)
	if win.show_mask and not was_closing:
		_show_mask(win.mask_opacity)
	elif win.show_mask and was_closing and _mask != null and is_instance_valid(_mask):
		_abort_mask_crossfade()
		_kill_mask_tween()
		_mask.color = Color(0, 0, 0, win.mask_opacity)
		_mask.visible = true
	_push_stack(layer, win)
	win._do_show(params)

	if win.show_mask and _mask != null and is_instance_valid(_mask):
		_restack_mask()

	if not was_closing:
		events.window_shown.emit(ui_name, win)
	if win.is_fullscreen:
		_refresh_occlusion()
	return win


func hide_ui(ui_name: String) -> void:
	var cached: Variant = _cache.get(ui_name, null)
	var win: UIFrameWindow = cached as UIFrameWindow if is_instance_valid(cached) else null
	if win == null or not win.is_showing():
		return
	win._window_state = UIBaseWindow.WindowState.CLOSING

	var _hide_duration: float = win.get_hide_anim_duration()
	if win.show_mask and _mask != null and is_instance_valid(_mask) and _mask.visible:
		if _mask_ref_count <= 1:
			_fade_out_mask(_hide_duration)
		else:
			_start_mask_crossfade(win, _hide_duration)
	await win._play_close_animation()
	if win._window_state != UIBaseWindow.WindowState.CLOSING:
		return
	var dlg: String = win.get_dlg_name()
	if dlg != "":
		Tracker.notify_dlg_closed(dlg)
	await win._do_hide()

	if win._window_state == UIBaseWindow.WindowState.SHOWING:
		return
	if win.show_mask:
		_hide_mask()
	var layer: int = win.ui_layer
	_pop_stack(layer, win)

	events.window_hidden.emit(ui_name, win)
	_refresh_occlusion()


func get_ui(ui_name: String) -> UIFrameWindow:
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		return cached as UIFrameWindow
	return null


func has_ui(ui_name: String) -> bool:
	return get_ui(ui_name) != null


func hide_all() -> void:
	for ui_name in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if is_instance_valid(cached) and (cached as UIFrameWindow).visible:
			hide_ui(ui_name)


func hide_all_except(names: Array[String]) -> void:
	for ui_name in _cache.keys():
		if ui_name in names:
			continue
		var cached: Variant = _cache[ui_name]
		if is_instance_valid(cached) and (cached as UIFrameWindow).visible:
			hide_ui(ui_name)


func _get_or_create(ui_name: String) -> UIFrameWindow:
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		var win : UIFrameWindow = cached as UIFrameWindow
		if win.get_parent() == null:
			get_tree().current_scene.add_child(win)
		else:
			win.get_parent().move_child(win, -1)
		return win
	var packed: PackedScene = load(_registry[ui_name])
	if packed == null:
		push_error("UIManager: cannot load '%s'" % _registry[ui_name])
		return null
	return _create_and_cache(ui_name, packed)


func _push_stack(layer: int, win: UIFrameWindow) -> void:
	if not _stacks.has(layer):
		_stacks[layer] = []
	var stack: Array = _stacks[layer]
	stack.erase(win)
	stack.append(win)


func _pop_stack(layer: int, win: UIFrameWindow) -> void:
	if _stacks.has(layer):
		_stacks[layer].erase(win)


func _ordered_windows() -> Array[UIFrameWindow]:
	var ordered: Array[UIFrameWindow] = []
	var layers: Array = _stacks.keys()
	layers.sort()
	for l: int in layers:
		for win: UIFrameWindow in _stacks[l]:
			ordered.append(win)
	return ordered


func _refresh_occlusion() -> void:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	var occluded: bool = false
	for i in range(ordered.size() - 1, -1, -1):
		var win: UIFrameWindow = ordered[i]
		if not is_instance_valid(win):
			continue
		var should_visible: bool = not occluded
		if should_visible and not win.visible:
			win.visible = true
			win.on_stack_top()
		elif not should_visible and win.visible:
			win.visible = false
			win.on_stack_bottom()
		if should_visible and win.is_fullscreen:
			occluded = true


func _assign_z_index(win: UIFrameWindow, layer: int) -> void:
	if not _next_z.has(layer):
		_next_z[layer] = layer
	if _next_z[layer] >= layer + UILayerConfig.Z_MAX:
		_compact_z_indices(layer)
	win.z_index = _next_z[layer]
	_next_z[layer] += UILayerConfig.Z_STEP


func _compact_z_indices(layer: int) -> void:
	var stack: Array = _stacks.get(layer, [])
	var visible_wins: Array[UIFrameWindow] = []
	for win: UIFrameWindow in stack:
		if win.visible:
			visible_wins.append(win)
	visible_wins.sort_custom(
		func(a: UIFrameWindow, b: UIFrameWindow) -> bool: return a.z_index < b.z_index
	)
	for i in visible_wins.size():
		visible_wins[i].z_index = layer + i * UILayerConfig.Z_STEP
	_next_z[layer] = layer + visible_wins.size() * UILayerConfig.Z_STEP


func set_layer_visible(layer: int, is_visible: bool) -> void:
	var stack: Array = _stacks.get(layer, [])
	for win: UIFrameWindow in stack:
		win.visible = is_visible


func get_window_count(layer: int) -> int:
	return _stacks.get(layer, []).size()


func warm_pool(ui_name: String) -> void:
	if _cache.has(ui_name):
		return
	_get_or_create(ui_name)
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		(cached as UIFrameWindow).visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_button()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button()
		get_viewport().set_input_as_handled()


func _on_back_button() -> void:
	var layers: Array = _stacks.keys()
	layers.sort()
	for i in range(layers.size() - 1, -1, -1):
		var stack: Array = _stacks[layers[i]]
		for j in range(stack.size() - 1, -1, -1):
			var win: UIFrameWindow = stack[j]
			if win.visible:
				win.on_escape()
				return


const _INPUT_BLOCKER_NAME: StringName = &"_InputBlocker"


func block_input_briefly(target: Control, duration: float = 1.5) -> void:
	if target == null or duration <= 0.0:
		return
	var existing := target.get_node_or_null(NodePath(_INPUT_BLOCKER_NAME))
	if existing != null:
		existing.queue_free()
	var blocker := Control.new()
	blocker.name = _INPUT_BLOCKER_NAME
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.z_index = 4095
	blocker.z_as_relative = false
	target.add_child(blocker)
	target.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if is_instance_valid(blocker):
				blocker.queue_free()
	)


func _show_mask(opacity: float) -> void:
	_mask_ref_count += 1

	_abort_mask_crossfade()
	if _mask == null or not is_instance_valid(_mask):
		_mask = ColorRect.new()
		_mask.name = "_GlobalMask"
		_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mask.mouse_filter = Control.MOUSE_FILTER_STOP
		get_tree().current_scene.add_child(_mask)

	_kill_mask_tween()
	_mask.color = Color(0, 0, 0, opacity)
	_mask.z_as_relative = false
	_mask.visible = true


func _hide_mask() -> void:
	_mask_ref_count -= 1
	if _mask_ref_count <= 0:
		_mask_ref_count = 0

		_kill_mask_secondary_tween()
		if _mask_secondary != null and is_instance_valid(_mask_secondary):
			_mask_secondary.visible = false
		if _mask != null and is_instance_valid(_mask):
			if _mask_tween == null or not _mask_tween.is_valid():
				_mask.visible = false
	elif _mask != null and is_instance_valid(_mask):
		if (
			_mask_secondary != null
			and is_instance_valid(_mask_secondary)
			and _mask_secondary.visible
		):
			_kill_mask_tween()
			_kill_mask_secondary_tween()
			var old_primary := _mask
			_mask = _mask_secondary
			_mask_secondary = old_primary
			old_primary.visible = false
			_mask_tween = null
		else:
			_restack_mask()


func _restack_mask() -> void:
	if _mask == null or not is_instance_valid(_mask):
		return
	var top_win: UIFrameWindow = null
	for ui_name: String in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if not is_instance_valid(cached):
			continue
		var win: UIFrameWindow = cached as UIFrameWindow
		if win.visible and win.show_mask and (top_win == null or win.z_index > top_win.z_index):
			top_win = win
	if top_win == null:
		return
	_mask.color = Color(0, 0, 0, top_win.mask_opacity)
	_mask.z_index = top_win.z_index - 1
	var parent: Node = _mask.get_parent()
	if parent != null and top_win.get_parent() == parent:
		var target: int = top_win.get_index()

		if _mask.get_index() < top_win.get_index():
			target -= 1
		parent.move_child(_mask, target)


func _fade_out_mask(duration: float) -> void:
	if _mask == null or not is_instance_valid(_mask):
		return
	_kill_mask_tween()
	if duration <= 0.0:
		_mask.visible = false
		return
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask, "color:a", 0.0, duration)
	_mask_tween.tween_callback(
		func() -> void:
			if _mask != null and is_instance_valid(_mask):
				_mask.visible = false
	)


func _kill_mask_tween() -> void:
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_tween = null


func _kill_mask_secondary_tween() -> void:
	if _mask_secondary_tween != null and _mask_secondary_tween.is_valid():
		_mask_secondary_tween.kill()
	_mask_secondary_tween = null


func _abort_mask_crossfade() -> void:
	if (
		_mask_secondary == null
		or not is_instance_valid(_mask_secondary)
		or not _mask_secondary.visible
	):
		return
	_kill_mask_tween()
	_kill_mask_secondary_tween()
	var old_primary := _mask
	_mask = _mask_secondary
	_mask_secondary = old_primary
	if old_primary != null and is_instance_valid(old_primary):
		old_primary.visible = false


func _start_mask_crossfade(closing_win: UIFrameWindow, duration: float) -> void:
	var next_top: UIFrameWindow = null
	for ui_name: String in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if not is_instance_valid(cached):
			continue
		var win: UIFrameWindow = cached as UIFrameWindow
		if win == closing_win or not win.visible or not win.show_mask:
			continue
		if next_top == null or win.z_index > next_top.z_index:
			next_top = win
	if next_top == null:
		_fade_out_mask(duration)
		return

	_kill_mask_secondary_tween()
	if _mask_secondary == null or not is_instance_valid(_mask_secondary):
		_mask_secondary = ColorRect.new()
		_mask_secondary.name = "_GlobalMask2"
		_mask_secondary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mask_secondary.mouse_filter = Control.MOUSE_FILTER_STOP
		get_tree().current_scene.add_child(_mask_secondary)
	_mask_secondary.z_as_relative = false
	_mask_secondary.z_index = next_top.z_index - 1
	_mask_secondary.color = Color(0, 0, 0, 0)
	_mask_secondary.visible = true

	var parent: Node = _mask_secondary.get_parent()
	if parent != null and next_top.get_parent() == parent:
		var target: int = next_top.get_index()
		if _mask_secondary.get_index() < next_top.get_index():
			target -= 1
		parent.move_child(_mask_secondary, target)

	_kill_mask_tween()
	if duration <= 0.0:
		_mask.visible = false
		_mask_secondary.color = Color(0, 0, 0, next_top.mask_opacity)
		return
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask, "color:a", 0.0, duration)
	_mask_tween.tween_callback(
		func() -> void:
			if _mask != null and is_instance_valid(_mask):
				_mask.visible = false
	)
	_mask_secondary_tween = create_tween()
	_mask_secondary_tween.tween_property(
		_mask_secondary, "color:a", next_top.mask_opacity, duration
	)


const _SAFE_TOP_GROUP: StringName = &"_safe_top"
const _SAFE_BOTTOM_GROUP: StringName = &"_safe_bottom"
const _SAFE_TOP_BASELINE_META: StringName = &"_safe_top_baseline"
const _SAFE_BOTTOM_BASELINE_META: StringName = &"_safe_bottom_baseline"
const _COLLAPSE_WHEN_TOP_SAFE_GROUP: StringName = &"_collapse_when_top_safe"
const _COLLAPSE_BASELINE_META: StringName = &"_collapse_when_top_safe_baseline"

const _SAFE_AREA_PAGES: Array[StringName] = [
	&"home",
	&"game",
	&"daily_game",
	&"win",
	&"fail",
	&"setting",
	&"bank",
]


func _apply_safe_area(page_name: String, node: Node) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return
	if not _SAFE_AREA_PAGES.has(StringName(page_name)):
		return
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	var top_inset: float = float(safe.position.y)
	var bottom_inset: float = float(win_size.y - (safe.position.y + safe.size.y))
	if top_inset <= 0.0 and bottom_inset <= 0.0:
		return
	for n in node.find_children("*", "Control", true, false):
		var c := n as Control
		var is_absolute: bool = is_equal_approx(c.anchor_top, c.anchor_bottom)
		if c.is_in_group(_SAFE_TOP_GROUP):
			if not c.has_meta(_SAFE_TOP_BASELINE_META):
				c.set_meta(_SAFE_TOP_BASELINE_META, Vector2(c.offset_top, c.offset_bottom))
			var baseline: Vector2 = c.get_meta(_SAFE_TOP_BASELINE_META)
			c.offset_top = baseline.x + top_inset
			if is_absolute:
				c.offset_bottom = baseline.y + top_inset
		if c.is_in_group(_SAFE_BOTTOM_GROUP):
			if not c.has_meta(_SAFE_BOTTOM_BASELINE_META):
				c.set_meta(_SAFE_BOTTOM_BASELINE_META, Vector2(c.offset_top, c.offset_bottom))
			var baseline: Vector2 = c.get_meta(_SAFE_BOTTOM_BASELINE_META)
			c.offset_bottom = baseline.y - bottom_inset
			if is_absolute:
				c.offset_top = baseline.x - bottom_inset
		if c.is_in_group(_COLLAPSE_WHEN_TOP_SAFE_GROUP):
			if not c.has_meta(_COLLAPSE_BASELINE_META):
				c.set_meta(
					_COLLAPSE_BASELINE_META,
					[c.visible, c.custom_minimum_size.y, c.size_flags_vertical]
				)
			var baseline: Array = c.get_meta(_COLLAPSE_BASELINE_META)
			if top_inset > 0.0:
				c.visible = false
				c.custom_minimum_size.y = 0.0
				c.size_flags_vertical = 0
			else:
				c.visible = bool(baseline[0])
				c.custom_minimum_size.y = float(baseline[1])
				c.size_flags_vertical = int(baseline[2])


var _loading: Dictionary = {}


func show_ui_async(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if not _registry.has(ui_name):
		push_error("UIManager: unknown ui '%s'" % ui_name)
		return null
	if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
		return show_ui(ui_name, params)

	if _loading.has(ui_name):
		while _loading.has(ui_name):
			await get_tree().process_frame
		if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
			return show_ui(ui_name, params)
		return null
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null:
		return null
	_create_and_cache(ui_name, packed)
	return show_ui(ui_name, params)


func warm_pool_async(ui_name: String) -> void:
	if _cache.has(ui_name) or _loading.has(ui_name):
		return
	if not _registry.has(ui_name):
		return
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null:
		return
	var win: UIFrameWindow = _create_and_cache(ui_name, packed)
	if win != null:
		win.visible = false


func _load_scene_async(ui_name: String) -> PackedScene:
	_loading[ui_name] = true
	var path: String = _registry[ui_name]
	ResourceLoader.load_threaded_request(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	_loading.erase(ui_name)
	if packed == null:
		push_error("UIManager: async load failed '%s'" % path)
	return packed


func _create_and_cache(ui_name: String, packed: PackedScene) -> UIFrameWindow:
	var node : Node = packed.instantiate()
	var win : UIFrameWindow = node as UIFrameWindow
	if win == null:
		push_error("UIManager: '%s' root must extend UIFrameWindow" % ui_name)
		node.queue_free()
		return null
	win._ui_name = ui_name
	get_tree().current_scene.add_child(win)
	_cache[ui_name] = win
	win._do_create()
	events.window_created.emit(ui_name, win)
	return win
