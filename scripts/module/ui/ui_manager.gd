## 全局窗口管理器：管理缓存、分层栈、遮罩、返回导航、安全区和异步预热。
extends Node

# ---- 注册表与缓存（key 都是 UiName 常量） ----
var _registry: Dictionary = {} # UiName -> 场景路径，_ready 时由 UIRegistry.build_registry 填充
var _cache: Dictionary = {} # UiName -> 已实例化的 UIFrameWindow（常驻复用，隐藏不销毁）
var _stacks: Dictionary = {} # layer -> 该层窗口栈，数组尾部是栈顶（最后显示的那个）
var _next_z: Dictionary = {} # layer -> 下一个可用的 z_index（每开一个窗口 +Z_STEP）
var events: UIEvents = UIEvents.new() # 对外事件总线：window_created / window_shown / window_hidden

var _guard_held_buttons: Array[BaseButton] = []
var _guard_active: bool = false

var _probe_enabled: bool = false
var _probe_pending: bool = false
var _probe_pos: Vector2 = Vector2.ZERO
var _probe_unhandled: bool = false
var _probe_btn: String = ""
var _probe_via_win: bool = false
var _probe_via_input: bool = false

# ---- 全局遮罩（运行时 new 出来的 ColorRect，不进场景文件） ----
var _mask: ColorRect = null # 主遮罩：盖住它下面所有内容
var _mask_ref_count: int = 0 # 引用计数：还有几个窗口要遮罩，归零才真的收起来
var _mask_tween: Tween = null # 主遮罩的淡入淡出 tween

var _mask_secondary: ColorRect = null # 副遮罩：两个带遮罩的窗口交接时做交叉淡化（旧的淡出、新的淡入）
var _mask_secondary_tween: Tween = null # 副遮罩的 tween

# ---- 埋点旁听 ----
var _tracker_observer: UITrackerObserver = null # 订阅 events.window_shown，把曝光上报转给 Tracker


func _ready() -> void:
	_registry = UIRegistry.build_registry()
	_tracker_observer = UITrackerObserver.new(events)

	get_viewport().size_changed.connect(_reapply_safe_area_all)
	_start_editor_layout_watcher()

	_start_canvas_watcher()

	_probe_enabled = not OS.has_feature("rel")
	if _probe_enabled:
		get_window().window_input.connect(_on_window_input_probe)

		set_process_input(true)


## 按注册表复用或创建窗口，处理重复显示与关闭中断，再更新层级、遮罩和遮挡关系。
func show_ui(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if not _registry.has(ui_name):
		push_error("UIManager: unknown ui '%s'" % ui_name)
		return null
	var win: UIFrameWindow = _get_or_create(ui_name)
	if win == null:
		return null
	if win.is_showing():
		push_warning(
			(
				"UIManager: show_ui('%s') called while already SHOWING — use hide_ui first or check caller logic"
				% ui_name
			)
		)

		(
			EventBus
			. emit_event(
				EventName.UI_SHOW_SKIPPED,
				{
					"ui": ui_name,
					"reason": "already_showing",
				}
			)
		)
		win.on_show(params)

		_reorder_window_tree()
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

		(
			EventBus
			. emit_event(
				EventName.UI_SHOW,
				{
					"ui": ui_name,
					"layer": layer,
					"fullscreen": win.is_fullscreen,
					"depth": get_window_count(layer),
				}
			)
		)
		if not _guard_held_buttons.is_empty():
			_guard_active = true
			if not _probe_enabled:
				set_process_input(true)
	if win.is_fullscreen:
		_refresh_occlusion()

	_reorder_window_tree()
	return win


## 等待关闭动画时窗口可能再次打开，因此逐阶段核对状态后才从显示栈移除。
func hide_ui(ui_name: String) -> void:
	var cached: Variant = _cache.get(ui_name, null)
	var win: UIFrameWindow = cached as UIFrameWindow if is_instance_valid(cached) else null
	if win == null or not win.is_showing():
		(
			EventBus
			. emit_event(
				EventName.UI_HIDE_SKIPPED,
				{
					"ui": ui_name,
					"reason": "not_cached" if win == null else "not_showing",
				}
			)
		)
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
		(
			EventBus
			. emit_event(
				EventName.UI_HIDE_ABORTED,
				{
					"ui": ui_name,
					"stage": "after_close_anim",
				}
			)
		)
		return
	var dlg: String = win.get_dlg_name()
	if dlg != "":
		Tracker.notify_dlg_closed(dlg)
	await win._do_hide()

	if win._window_state == UIBaseWindow.WindowState.SHOWING:
		(
			EventBus
			. emit_event(
				EventName.UI_HIDE_ABORTED,
				{
					"ui": ui_name,
					"stage": "after_on_hide",
				}
			)
		)
		return
	if win.show_mask:
		_hide_mask(win)
	var layer: int = win.ui_layer
	_pop_stack(layer, win)

	if dlg == "" and win.get_scr_name() != "":
		Tracker.notify_scr_closed(_current_top_source())

	events.window_hidden.emit(ui_name, win)

	(
		EventBus
		. emit_event(
			EventName.UI_HIDE,
			{
				"ui": ui_name,
				"layer": layer,
				"depth": get_window_count(layer),
			}
		)
	)
	_refresh_occlusion()


func destroy_ui(ui_name: String) -> void:
	var win: UIFrameWindow = get_ui(ui_name)
	if win == null:
		return
	var show_version: int = win._show_version
	if win.is_showing():
		hide_ui(ui_name)

	while (
		is_instance_valid(win)
		and _cache.get(ui_name, null) == win
		and win._show_version == show_version
		and win.get_window_state() == UIBaseWindow.WindowState.CLOSING
	):
		await get_tree().process_frame
	if not is_instance_valid(win) or get_ui(ui_name) != win:
		return

	if win._show_version != show_version or not win.is_hidden() or _is_in_stack(ui_name):
		return

	_cache.erase(ui_name)
	await win._do_destroy()
	if is_instance_valid(win):
		win.queue_free()


func await_hidden(ui_name: StringName) -> void:
	if not _is_in_stack(ui_name):
		return
	while true:
		var payload: Array = await events.window_hidden
		if payload[0] == ui_name:
			return


func _is_in_stack(ui_name: StringName) -> bool:
	var win: UIFrameWindow = get_ui(ui_name)
	if win == null:
		return false
	var stack: Array = _stacks.get(win.ui_layer, [])
	return stack.has(win)


# ================= 查询 =================
func get_ui(ui_name: String) -> UIFrameWindow:
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		return cached as UIFrameWindow
	return null


## 这个页面当前是否已经创建过（只看缓存，不触发创建）
func has_ui(ui_name: String) -> bool:
	return get_ui(ui_name) != null


func is_any_loading() -> bool:
	return not _loading.is_empty()


# ================= 批量收起 =================
func hide_all() -> void:
	for ui_name in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if is_instance_valid(cached) and (cached as UIFrameWindow).visible:
			hide_ui(ui_name)


func hide_all_showing_except(names: Array) -> void:
	var snapshot: Array = _cache.keys()
	for ui_name in snapshot:
		if ui_name in names:
			continue
		var cached: Variant = _cache.get(ui_name, null)
		if is_instance_valid(cached) and (cached as UIFrameWindow).is_showing():
			await hide_ui(ui_name)


## 收起除名单外的所有已显示页面（名单里的保持原样）
func hide_all_except(names: Array[String]) -> void:
	for ui_name in _cache.keys():
		if ui_name in names:
			continue
		var cached: Variant = _cache[ui_name]
		if is_instance_valid(cached) and (cached as UIFrameWindow).visible:
			hide_ui(ui_name)


func _scene_path(ui_name: String) -> String:
	var v: Variant = _registry.get(ui_name, "")
	if v is Callable:
		return (v as Callable).call() as String
	return v as String


func _evict_cached(ui_name: String) -> void:
	var cached: Variant = _cache.get(ui_name, null)
	_cache.erase(ui_name)
	if is_instance_valid(cached):
		(cached as Node).queue_free()


func _get_or_create(ui_name: String) -> UIFrameWindow:
	var want_path: String = _scene_path(ui_name)
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		var win := cached as UIFrameWindow

		if (
			win.scene_file_path == want_path
			or win.get_window_state() != UIBaseWindow.WindowState.HIDDEN
		):
			if win.get_parent() == null:
				get_tree().current_scene.add_child(win)
			else:
				win.get_parent().move_child(win, -1)
			return win
		_evict_cached(ui_name)
	if not _loading.is_empty():
		push_error("UIManager: 同步 load '%s' 与后台加载 %s 重叠,存在死锁风险" % [ui_name, _loading.keys()])
	var packed: PackedScene = load(want_path)
	if packed == null:
		push_error("UIManager: cannot load '%s'" % want_path)
		return null
	return _create_and_cache(ui_name, packed)


## 入栈：同层做过就把旧的挪到栈顶（重新显示算最新）
func _push_stack(layer: int, win: UIFrameWindow) -> void:
	if not _stacks.has(layer):
		_stacks[layer] = []
	var stack: Array = _stacks[layer]
	stack.erase(win)
	stack.append(win)


## 出栈：把窗口从它那一层的栈里删掉
func _pop_stack(layer: int, win: UIFrameWindow) -> void:
	if _stacks.has(layer):
		_stacks[layer].erase(win)


func _reorder_window_tree() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for win: UIFrameWindow in _ordered_windows():
		if is_instance_valid(win) and win.get_parent() == scene:
			scene.move_child(win, -1)

	if _mask != null and is_instance_valid(_mask) and _mask.visible:
		_restack_mask()


func _ordered_windows() -> Array[UIFrameWindow]:
	var ordered: Array[UIFrameWindow] = []
	var layers: Array = _stacks.keys()
	layers.sort()
	for l: int in layers:
		for entry in _stacks[l]:
			if not is_instance_valid(entry):
				continue
			var win := entry as UIFrameWindow
			if win != null:
				ordered.append(win)
	return ordered


func _current_top_source() -> String:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	for i in range(ordered.size() - 1, -1, -1):
		var win: UIFrameWindow = ordered[i]
		if not is_instance_valid(win):
			continue
		var dlg: String = win.get_dlg_name()
		if dlg != "":
			return dlg
		var scr: String = win.get_scr_name()
		if scr != "":
			return scr
	return ""


## 从顶层向下更新窗口可见性；全屏窗口遮挡下层，同时通知遮挡状态变化。
func _refresh_occlusion() -> void:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	var occluded: bool = false

	var turned_on: PackedStringArray = PackedStringArray()
	var turned_off: PackedStringArray = PackedStringArray()
	for i in range(ordered.size() - 1, -1, -1):
		var win: UIFrameWindow = ordered[i]
		if not is_instance_valid(win):
			continue
		var should_visible: bool = not occluded
		if should_visible and not win.visible:
			win.visible = true
			win.on_stack_top()
			turned_on.append(win.get_ui_name())
		elif not should_visible and win.visible:
			win.visible = false
			win.on_stack_bottom()
			turned_off.append(win.get_ui_name())
		if should_visible and win.is_fullscreen:
			occluded = true
	if not turned_on.is_empty() or not turned_off.is_empty():
		var occ_payload: Dictionary = {}
		if not turned_off.is_empty():
			occ_payload["hidden"] = ",".join(turned_off)
		if not turned_on.is_empty():
			occ_payload["shown"] = ",".join(turned_on)
		EventBus.emit_event(EventName.UI_OCCLUSION, occ_payload)


## 分配 z_index：每层从 layer 基址起按 Z_STEP 递增，保证后开的更高
func _assign_z_index(win: UIFrameWindow, layer: int) -> void:
	# 该层第一次用到，起点就是层基址
	if not _next_z.has(layer):
		_next_z[layer] = layer
	# 涨到上限就先重排一次，避免无限增长
	if _next_z[layer] >= layer + UILayerConfig.Z_MAX:
		_compact_z_indices(layer)
	# 取当前值，再为下一个窗口预留
	win.z_index = _next_z[layer]
	_next_z[layer] += UILayerConfig.Z_STEP


func _compact_z_indices(layer: int) -> void:
	var stack: Array = _stacks.get(layer, [])
	var idx: int = 0
	for entry in stack:
		if not is_instance_valid(entry):
			continue
		var win := entry as UIFrameWindow
		if win == null:
			continue
		win.z_index = layer + idx * UILayerConfig.Z_STEP
		idx += 1
	_next_z[layer] = layer + idx * UILayerConfig.Z_STEP
	EventBus.emit_event(EventName.UI_Z_COMPACT, {"layer": layer, "count": idx})


func set_layer_visible(layer: int, is_visible: bool) -> void:
	var stack: Array = _stacks.get(layer, [])
	for entry in stack:
		if not is_instance_valid(entry):
			continue
		var win := entry as UIFrameWindow
		if win != null:
			win.visible = is_visible


## 某层栈里有几个窗口（含当前不可见的）
func get_window_count(layer: int) -> int:
	return _stacks.get(layer, []).size()


func is_top_of_stack(win: UIFrameWindow) -> bool:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	if ordered.is_empty():
		return false
	return ordered[-1] == win


func debug_dump_stack() -> String:
	var state_names: Array[String] = [
		"INVALID", "CREATING", "SHOWING", "HIDDEN", "CLOSING", "DESTROYED"
	]
	var lines: Array[String] = ["──── UI 栈 dump ────"]
	var name_of: Dictionary = {}
	for k: String in _cache.keys():
		var c: Variant = _cache[k]
		if is_instance_valid(c):
			name_of[c] = k
	var in_stack: Dictionary = {}
	var layers: Array = _stacks.keys()
	layers.sort()
	for l: int in layers:
		var stack: Array = _stacks[l]
		if stack.is_empty():
			continue
		lines.append("[Layer %d] 共 %d 个" % [l, stack.size()])
		for i in stack.size():
			if not is_instance_valid(stack[i]):
				lines.append("  #%d <已释放>" % i)
				continue
			var win := stack[i] as UIFrameWindow
			if win == null:
				lines.append("  #%d <非 UIFrameWindow>" % i)
				continue
			in_stack[win] = true
			var nm: String = str(name_of.get(win, win.name))
			var st: int = win.get_window_state()
			var flags: String = ""
			if win.is_fullscreen:
				flags += " FS"
			if win.show_mask:
				flags += " MASK"
			var warn: String = ""
			if st != UIBaseWindow.WindowState.SHOWING and st != UIBaseWindow.WindowState.CLOSING:
				warn += " ⚠僵尸(栈内非SHOWING)"
			if st == UIBaseWindow.WindowState.SHOWING and not win.visible:
				warn += " ⚠SHOWING但不可见"
			lines.append(
				(
					"  #%d %s state=%s vis=%s z=%d%s%s"
					% [i, nm.rpad(22), state_names[st], str(win.visible), win.z_index, flags, warn]
				)
			)
	var orphans: Array[String] = []
	for k: String in _cache.keys():
		var c: Variant = _cache[k]
		if not is_instance_valid(c):
			continue
		var win: UIFrameWindow = c as UIFrameWindow
		if not in_stack.has(win) and win.visible:
			orphans.append(
				(
					"  %s state=%s z=%d ⚠可见但不在栈(游离孤儿)"
					% [k, state_names[win.get_window_state()], win.z_index]
				)
			)
	if not orphans.is_empty():
		lines.append("──── 游离(不在栈却 visible) ────")
		lines.append_array(orphans)
	var mask_on: bool = _mask != null and is_instance_valid(_mask) and _mask.visible

	if _mask != null and is_instance_valid(_mask):
		lines.append(
			(
				"mask: ref=%d visible=%s z=%d alpha=%.2f 树序=%d/%d"
				% [
					_mask_ref_count,
					str(mask_on),
					_mask.z_index,
					_mask.color.a,
					_mask.get_index(),
					_mask.get_parent().get_child_count() if _mask.get_parent() != null else -1
				]
			)
		)
	else:
		lines.append("mask: ref=%d 实例未创建" % _mask_ref_count)
	return "\n".join(lines)


## 预热：提前实例化并保持隐藏，避免第一次打开时卡在加载
func warm_pool(ui_name: String) -> void:
	if _cache.has(ui_name):
		return
	_get_or_create(ui_name)
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		(cached as UIFrameWindow).visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_button("back_key")


func is_any_button_held() -> bool:
	for held: BaseButton in _guard_held_buttons:
		if is_instance_valid(held) and held.is_visible_in_tree():
			return true
	return false


func _guard_held(b: BaseButton) -> void:
	_guard_held_buttons.append(b)

	if _probe_pending:
		_probe_btn = String(b.name)


func _guard_released(b: BaseButton) -> void:
	_guard_held_buttons.erase(b)

	if _guard_held_buttons.is_empty() and _guard_active:
		_guard_active = false
		if not _probe_enabled:
			set_process_input(false)


func _input(event: InputEvent) -> void:
	if _probe_enabled and _is_probe_press(event):
		_probe_begin(
			(
				(event as InputEventMouseButton).position
				if event is InputEventMouseButton
				else (event as InputEventScreenTouch).position
			),
			false
		)
	if not _guard_active:
		return
	var is_release: bool = (
		(event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed)
	)
	if not is_release:
		return
	get_viewport().set_input_as_handled()
	_guard_active = false
	var blocked: PackedStringArray = PackedStringArray()
	for b in _guard_held_buttons:
		if not is_instance_valid(b):
			continue
		blocked.append(String(b.name))

		var was_disabled := b.disabled
		b.disabled = true
		b.disabled = was_disabled
	_guard_held_buttons.clear()
	if not _probe_enabled:
		set_process_input(false)

	(
		EventBus
		. emit_event(
			EventName.UI_TAP_BLOCKED,
			{
				"btns": ",".join(blocked),
				"count": blocked.size(),
			}
		)
	)


func _unhandled_input(event: InputEvent) -> void:
	if _probe_pending and _is_probe_press(event):
		_probe_unhandled = true
	if event.is_action_pressed("ui_cancel"):
		_on_back_button("esc")
		get_viewport().set_input_as_handled()


func get_top_window(excluded_ui_name: StringName = &"") -> UIFrameWindow:
	var layers: Array = _stacks.keys()
	layers.sort()
	for i in range(layers.size() - 1, -1, -1):
		var stack: Array = _stacks[layers[i]]
		for j in range(stack.size() - 1, -1, -1):
			if not is_instance_valid(stack[j]):
				continue
			var win := stack[j] as UIFrameWindow
			if (
				win != null
				and win.visible
				and (excluded_ui_name == &"" or win.get_ui_name() != excluded_ui_name)
			):
				return win
	return null


func get_top_ui_name() -> String:
	var win: UIFrameWindow = get_top_window()
	return win.get_ui_name() if win != null else ""


func get_top_ui_name_excluding(excluded_ui_name: StringName) -> String:
	var win: UIFrameWindow = get_top_window(excluded_ui_name)
	return win.get_ui_name() if win != null else ""


func _on_back_button(src: String) -> void:
	var win: UIFrameWindow = get_top_window()
	if win != null:
		(
			EventBus
			. emit_event(
				EventName.UI_BACK_KEY,
				{
					"src": src,
					"to": win.get_ui_name(),
					"handled": true,
				}
			)
		)
		win.on_escape()
		return

	EventBus.emit_event(EventName.UI_BACK_KEY, {"src": src, "to": "", "handled": false})


# ================= 输入保护 =================
const _INPUT_BLOCKER_NAME: StringName = &"_InputBlocker" # 挡板节点名，重入时先找到旧的那块

const _INPUT_BLOCKER_TIMER_NAME: StringName = &"_Timer"


func block_input_briefly(target: Control, duration: float = 1.5) -> void:
	if target == null or duration <= 0.0:
		return
	var blocker: Control = target.get_node_or_null(NodePath(_INPUT_BLOCKER_NAME)) as Control

	if blocker != null and blocker.is_queued_for_deletion():
		blocker.name = &"_InputBlockerDying"
		blocker = null
	if blocker == null:
		blocker = Control.new()
		blocker.name = _INPUT_BLOCKER_NAME
		blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		blocker.z_index = 4095
		blocker.z_as_relative = false
		var timer := Timer.new()
		timer.name = _INPUT_BLOCKER_TIMER_NAME
		timer.one_shot = true

		timer.process_mode = Node.PROCESS_MODE_ALWAYS
		timer.timeout.connect(blocker.queue_free)
		blocker.add_child(timer)
		target.add_child(blocker)
	else:
		target.move_child(blocker, -1)

	(blocker.get_node(NodePath(_INPUT_BLOCKER_TIMER_NAME)) as Timer).start(duration)


func is_covered_by_mask(control: Control) -> bool:
	if control == null:
		return false
	if _mask == null or not is_instance_valid(_mask) or not _mask.visible or _mask.color.a <= 0.01:
		return false
	var win: UIFrameWindow = _find_owner_window(control)
	if win == null:
		return false
	return win.z_index < _mask.z_index


func _find_owner_window(node: Node) -> UIFrameWindow:
	var n: Node = node
	while n != null:
		if n is UIFrameWindow:
			return n as UIFrameWindow
		n = n.get_parent()
	return null


func _show_mask(opacity: float) -> void:
	_mask_ref_count += 1
	EventBus.emit_event(EventName.UI_MASK, {"action": "show", "ref": _mask_ref_count})

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


func fade_out_mask_early(duration: float = 0.2) -> void:
	if _mask == null or not is_instance_valid(_mask) or not _mask.visible:
		return
	_kill_mask_tween()
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask, "color:a", 0.0, duration)


func set_window_mask_opacity(window: UIFrameWindow, opacity: float, duration: float = 0.0) -> void:
	if not is_instance_valid(window) or not window.show_mask or not window.is_showing():
		return
	window.mask_opacity = clampf(opacity, 0.0, 1.0)
	if _top_mask_window(null) != window or not is_instance_valid(_mask):
		return
	_abort_mask_crossfade()
	_kill_mask_tween()
	if duration <= 0.0:
		_mask.color.a = window.mask_opacity
		return
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask, "color:a", window.mask_opacity, duration)


func _hide_mask(closing: UIFrameWindow = null) -> void:
	_mask_ref_count -= 1
	EventBus.emit_event(EventName.UI_MASK, {"action": "hide", "ref": maxi(0, _mask_ref_count)})
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

			_restack_mask(closing)
		else:
			var remaining: UIFrameWindow = _top_mask_window(closing)
			if remaining != null:
				_kill_mask_tween()
				_mask.visible = true
				_restack_mask(closing)


func _top_mask_window(exclude: UIFrameWindow) -> UIFrameWindow:
	var top_win: UIFrameWindow = null
	for win: UIFrameWindow in _ordered_windows():
		if not is_instance_valid(win) or win == exclude or not win.show_mask:
			continue
		if top_win == null or win.z_index > top_win.z_index:
			top_win = win
	return top_win


func _restack_mask(exclude: UIFrameWindow = null) -> void:
	if _mask == null or not is_instance_valid(_mask):
		return
	var top_win: UIFrameWindow = _top_mask_window(exclude)
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


## 遮罩整体淡出；duration <= 0 就直接隐藏
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


## 杀掉主遮罩的 tween 并置空（凡是要直接改遮罩状态的地方都先调它）
func _kill_mask_tween() -> void:
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_tween = null


## 同上，针对副遮罩
func _kill_mask_secondary_tween() -> void:
	if _mask_secondary_tween != null and _mask_secondary_tween.is_valid():
		_mask_secondary_tween.kill()
	_mask_secondary_tween = null


## 交叉淡化还没播完就被打断：把副遮罩顶上主位，旧主遮罩直接隐藏
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
	EventBus.emit_event(EventName.UI_MASK, {"action": "crossfade", "ref": _mask_ref_count})

	var next_top: UIFrameWindow = _top_mask_window(closing_win)
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


# ================= 刘海屏 / 安全区适配 =================
const _SAFE_TOP_GROUP: StringName = &"_safe_top" # 需要贴顶部安全区的节点分组名（.tscn 里挂 group）
const _SAFE_BOTTOM_GROUP: StringName = &"_safe_bottom" # 需要贴底部安全区的节点分组名
const _SAFE_TOP_BASELINE_META: StringName = &"_safe_top_baseline" # 顶部节点基线 offset 的 meta 键：只记一次，避免反复叠加
const _SAFE_BOTTOM_BASELINE_META: StringName = &"_safe_bottom_baseline" # 底部节点基线 offset 的 meta 键
const _COLLAPSE_WHEN_TOP_SAFE_GROUP: StringName = &"_collapse_when_top_safe" # 顶部有刘海时应该收起来的分组名
const _COLLAPSE_BASELINE_META: StringName = &"_collapse_when_top_safe_baseline" # 这类节点 可见性 / 最小高度 / 垂直尺寸标志 的基线 meta 键

const _SAFE_AREA_PAGES: Array[StringName] = [
	&"home",
	&"game",
	&"daily_game",
	&"win",
	&"fail",
	&"setting",
	&"bank",
	&"rank_activity_change",
	&"rank_activity_change_v2",
	&"rank_activity_page",
	&"subscription",
	&"rank_activity_offline",
]

var _dbg_safe_on: bool = false
var _dbg_safe_touched: bool = false
var _dbg_safe_top: float = 0.0
var _dbg_safe_bottom: float = 0.0


func debug_set_safe_inset(top: float, bottom: float) -> void:
	_dbg_safe_touched = true
	_dbg_safe_on = true
	_dbg_safe_top = maxf(0.0, top)
	_dbg_safe_bottom = maxf(0.0, bottom)

	apply_design_canvas()


func debug_clear_safe_inset() -> void:
	_dbg_safe_on = false
	_dbg_safe_top = 0.0
	_dbg_safe_bottom = 0.0
	apply_design_canvas()


const _LIVE_CFG_PATH := "user://resolution_picker_live.cfg"
var _live_rev: int = -1
var _live_timer: Timer = null
var _live_last_vh: float = -1.0


func _start_editor_layout_watcher() -> void:
	if not OS.has_feature("editor"):
		return
	_live_timer = Timer.new()
	_live_timer.wait_time = 0.4
	_live_timer.autostart = true
	_live_timer.timeout.connect(_poll_live_layout)
	add_child(_live_timer)
	_poll_live_layout()


func _poll_live_layout() -> void:
	var vh: float = get_viewport().get_visible_rect().size.y
	if not is_equal_approx(vh, _live_last_vh):
		_live_last_vh = vh
		_reapply_safe_area_all()

	var cfg := ConfigFile.new()
	if cfg.load(_LIVE_CFG_PATH) != OK:
		return
	var rev: int = int(cfg.get_value("live", "rev", 0))
	if rev == _live_rev:
		return
	_live_rev = rev
	var w: int = int(cfg.get_value("live", "w", 0))
	var h: int = int(cfg.get_value("live", "h", 0))
	if w > 0 and h > 0 and DisplayServer.window_get_size() != Vector2i(w, h):
		DisplayServer.window_set_size(Vector2i(w, h))
	var top: float = float(cfg.get_value("live", "notch_top", 0.0))
	var bottom: float = float(cfg.get_value("live", "notch_bottom", 0.0))
	if top > 0.0 or bottom > 0.0:
		debug_set_safe_inset(top, bottom)
	else:
		debug_clear_safe_inset()


func _reapply_safe_area_all() -> void:
	for ui_name in _cache:
		var win: UIFrameWindow = _cache[ui_name]
		if not is_instance_valid(win):
			continue
		for n in win.find_children("*", "Control", true, false):
			if n.has_method("debug_recompute"):
				n.call("debug_recompute")
		_apply_safe_area(String(ui_name), win)


const DESIGN_W: int = 1080

const DESIGN_MIN_AVAIL_H: int = 1920

const _CANVAS_POLL_SEC: float = 0.05
const _CANVAS_POLL_TIMEOUT_SEC: float = 3.0

var _canvas_poll_timer: Timer = null
var _canvas_poll_elapsed: float = 0.0


func _is_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


## 根据窗口与安全区计算设计画布，设置缩放并重新应用各窗口安全边距。
func apply_design_canvas() -> void:
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var phys: Vector2 = _safe_insets_physical()
	var avail_h: float = float(win.y) - phys.x - phys.y
	var design_h: int = DESIGN_MIN_AVAIL_H
	if avail_h > 0.0:
		design_h = maxi(
			DESIGN_MIN_AVAIL_H, int(ceil(float(DESIGN_MIN_AVAIL_H) * float(win.y) / avail_h))
		)
	var root: Window = get_tree().root
	root.content_scale_size = Vector2i(DESIGN_W, design_h)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_reapply_safe_area_all()


func _start_canvas_watcher() -> void:
	if not _is_mobile() or is_safe_area_ready():
		return
	_canvas_poll_timer = Timer.new()
	_canvas_poll_timer.wait_time = _CANVAS_POLL_SEC
	_canvas_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas_poll_timer.timeout.connect(_on_canvas_poll)
	add_child(_canvas_poll_timer)
	_canvas_poll_timer.start()


func _on_canvas_poll() -> void:
	_canvas_poll_elapsed += _CANVAS_POLL_SEC
	if is_safe_area_ready():
		apply_design_canvas()
		_stop_canvas_watcher()
		return
	if _canvas_poll_elapsed >= _CANVAS_POLL_TIMEOUT_SEC:
		_stop_canvas_watcher()


func _stop_canvas_watcher() -> void:
	if _canvas_poll_timer != null and is_instance_valid(_canvas_poll_timer):
		_canvas_poll_timer.stop()
		_canvas_poll_timer.queue_free()
	_canvas_poll_timer = null


func is_safe_area_ready() -> bool:
	if not _is_mobile():
		return true
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	return safe.size.x > 0 and safe.size.y > 0


func _safe_insets_physical() -> Vector2:
	if _dbg_safe_on:
		return Vector2(_dbg_safe_top, _dbg_safe_bottom)
	if not _is_mobile() or not is_safe_area_ready():
		return Vector2.ZERO
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.y <= 0:
		return Vector2.ZERO

	return Vector2(
		maxf(0.0, float(safe.position.y)),
		maxf(0.0, float(win_size.y - (safe.position.y + safe.size.y))),
	)


func get_safe_insets() -> Vector2:
	if _dbg_safe_on:
		return Vector2(_dbg_safe_top, _dbg_safe_bottom)
	if not _is_mobile():
		return Vector2.ZERO
	var phys: Vector2 = _safe_insets_physical()
	var win_y: int = DisplayServer.window_get_size().y
	if win_y <= 0:
		return Vector2.ZERO
	return phys * (float(get_viewport().get_visible_rect().size.y) / float(win_y))


func _apply_safe_area(page_name: String, node: Node) -> void:
	if not _SAFE_AREA_PAGES.has(StringName(page_name)):
		return
	if not _dbg_safe_on and not _is_mobile() and not _dbg_safe_touched:
		return
	var insets: Vector2 = get_safe_insets()
	var top_inset: float = insets.x
	var bottom_inset: float = insets.y

	if top_inset <= 0.0 and bottom_inset <= 0.0 and not _dbg_safe_touched:
		return
	var controls: Array[Node] = node.find_children("*", "Control", true, false)
	for child: Node in controls:
		var control: Control = child as Control
		var is_absolute: bool = is_equal_approx(control.anchor_top, control.anchor_bottom)
		if control.is_in_group(_SAFE_TOP_GROUP):
			if not control.has_meta(_SAFE_TOP_BASELINE_META):
				control.set_meta(
					_SAFE_TOP_BASELINE_META, Vector2(control.offset_top, control.offset_bottom)
				)
			var baseline: Vector2 = control.get_meta(_SAFE_TOP_BASELINE_META)
			control.offset_top = baseline.x + top_inset
			if is_absolute:
				control.offset_bottom = baseline.y + top_inset
		if control.is_in_group(_SAFE_BOTTOM_GROUP):
			if not control.has_meta(_SAFE_BOTTOM_BASELINE_META):
				control.set_meta(
					_SAFE_BOTTOM_BASELINE_META, Vector2(control.offset_top, control.offset_bottom)
				)
			var baseline: Vector2 = control.get_meta(_SAFE_BOTTOM_BASELINE_META)
			control.offset_bottom = baseline.y - bottom_inset
			if is_absolute:
				control.offset_top = baseline.x - bottom_inset
		if control.is_in_group(_COLLAPSE_WHEN_TOP_SAFE_GROUP):
			if not control.has_meta(_COLLAPSE_BASELINE_META):
				control.set_meta(
					_COLLAPSE_BASELINE_META,
					[control.visible, control.custom_minimum_size.y, control.size_flags_vertical]
				)
			var baseline: Array = control.get_meta(_COLLAPSE_BASELINE_META)
			if top_inset > 0.0:
				control.visible = false
				control.custom_minimum_size.y = 0.0
				control.size_flags_vertical = 0
			else:
				control.visible = bool(baseline[0])
				control.size_flags_vertical = int(baseline[2])

				if control.has_method("debug_recompute"):
					control.call("debug_recompute")
				else:
					control.custom_minimum_size.y = float(baseline[1])


# ================= 异步加载 / 预热 =================
var _loading: Dictionary = {} # UiName -> 正在后台加载中，用来做并发去重

var _async_warm_allowed: bool = true


func close_async_warm_window() -> void:
	_async_warm_allowed = false


## 合并同一窗口的并发加载请求，资源就绪并缓存实例后进入统一显示流程。
func show_ui_async(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if not _registry.has(ui_name):
		push_error("UIManager: unknown ui '%s'" % ui_name)
		return null
	if not _async_warm_allowed:
		return show_ui(ui_name, params)
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
	if not _async_warm_allowed:
		warm_pool(ui_name)
		return
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null:
		return

	if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
		return
	var win: UIFrameWindow = _create_and_cache(ui_name, packed)
	if win != null:
		win.visible = false


const _ASYNC_LOAD_TIMEOUT_MS: int = 25000


func _load_scene_async(ui_name: String) -> PackedScene:
	_loading[ui_name] = true
	var path: String = _scene_path(ui_name)
	ResourceLoader.load_threaded_request(path)
	var t0: int = Time.get_ticks_msec()

	EventBus.emit_event(EventName.UI_ASYNC_LOAD, {"ui": ui_name, "phase": "start"})
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if Time.get_ticks_msec() - t0 > _ASYNC_LOAD_TIMEOUT_MS:
			push_error("UIManager: async load timeout ui=%s path=%s" % [ui_name, path])
			_loading.erase(ui_name)
			(
				EventBus
				. emit_event(
					EventName.UI_ASYNC_LOAD,
					{
						"ui": ui_name,
						"phase": "timeout",
						"ms": Time.get_ticks_msec() - t0,
					}
				)
			)
			return null
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	_loading.erase(ui_name)
	if packed == null:
		push_error("UIManager: async load failed '%s'" % path)
	(
		EventBus
		. emit_event(
			EventName.UI_ASYNC_LOAD,
			{
				"ui": ui_name,
				"phase": "done" if packed != null else "failed",
				"ms": Time.get_ticks_msec() - t0,
			}
		)
	)
	return packed


func _create_and_cache(ui_name: String, packed: PackedScene) -> UIFrameWindow:
	var node := packed.instantiate()
	var win := node as UIFrameWindow
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


func _is_probe_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	return false


func _on_window_input_probe(event: InputEvent) -> void:
	if not _is_probe_press(event):
		return
	if event is InputEventMouseButton:
		_probe_begin((event as InputEventMouseButton).position, true)
	else:
		_probe_begin((event as InputEventScreenTouch).position, true)


func _probe_begin(pos: Vector2, from_window_signal: bool) -> void:
	if not _probe_pending:
		_probe_pending = true
		_probe_unhandled = false
		_probe_btn = ""
		_probe_via_win = false
		_probe_via_input = false
		_probe_pos = pos

		call_deferred("_flush_probe")
	if from_window_signal:
		_probe_via_win = true
	else:
		_probe_via_input = true


func _flush_probe() -> void:
	if not _probe_pending:
		return
	_probe_pending = false
	var via: PackedStringArray = PackedStringArray()
	if _probe_via_win:
		via.append("win")
	if _probe_via_input:
		via.append("input")
	var payload: Dictionary = {
		"x": int(_probe_pos.x),
		"y": int(_probe_pos.y),
		"node": _probe_hovered_path(),
		"eaten": not _probe_unhandled,
		"via": ",".join(via),
	}

	if _probe_btn != "":
		payload["btn"] = _probe_btn
	EventBus.emit_event(EventName.INPUT_TAP, payload)


func _probe_hovered_path() -> String:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null or not is_instance_valid(hovered):
		return ""

	var path: String = String(hovered.get_path()).trim_prefix("/root/")

	return (
		"%s|%s|%s"
		% [
			path,
			_mouse_filter_name(hovered.get_mouse_filter_with_override()),
			hovered.get_class(),
		]
	)


func _mouse_filter_name(f: int) -> String:
	match f:
		Control.MOUSE_FILTER_STOP:
			return "STOP"
		Control.MOUSE_FILTER_PASS:
			return "PASS"
		Control.MOUSE_FILTER_IGNORE:
			return "IGNORE"
	return "unknown(%d)" % f
