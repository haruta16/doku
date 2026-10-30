## 通用窗口层行为验收；tools/run_ui_framework_tests.py 只复制 UI 核心运行同一份用例。
extends SceneTree

class ImmediateCloseWindow extends UIFrameWindow:
	var close_on_show: bool = true
	var open_animation_calls: int = 0

	func on_show(_params: Dictionary = {}) -> void:
		if close_on_show:
			close_requested.emit()

	func _play_open_animation() -> void:
		open_animation_calls += 1

class DestroyParent extends UIBaseWindow:
	var events: Array[String] = []
	func on_destroy() -> void:
		events.append("parent")

class SafeAreaManager extends UIWindowManager:
	var safe_area_calls: int = 0
	func _apply_safe_area(_page_name: String, _node: Node) -> void:
		safe_area_calls += 1

class DelayedChild extends UIChildWindow:
	signal released
	var events: Array[String] = []
	var hide_calls: int = 0
	func on_hide() -> void:
		hide_calls += 1
		await released
	func on_destroy() -> void:
		events.append("child")

class OcclusionWindow extends UIFrameWindow:
	var stack_events: Array[String] = []
	var bottom_action: Callable
	func on_stack_top() -> void:
		stack_events.append("top")
	func on_stack_bottom() -> void:
		stack_events.append("bottom")
		if bottom_action.is_valid():
			bottom_action.call()

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var isolated: bool = ProjectSettings.get_setting("test/ui_framework_isolated", false)
	if not isolated and not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_ui_framework_tests.py or tools/run_validation.py")
		quit(2)
		return
	if isolated:
		_check(root.get_child_count() == 0, "minimal project has no product Autoload")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	current_scene = host
	await _test_child_teardown(host)
	await _test_child_creation(host)
	await _test_frame_creation(host)

	var template := UIFrameWindow.new()
	template.play_open_sound = true
	template.size = Vector2(100, 100)
	_add_button(template, "CloseBtn")
	var scene := PackedScene.new()
	_check(scene.pack(template) == OK, "pack generic window scene")
	template.free()
	var path: String = "res://ui_framework_fixture.tscn"
	_check(ResourceSaver.save(scene, path) == OK, "fixture stays in isolated project")
	var registry: Dictionary = {"shared": path, "high": path, "full": path, "async": path, "warm": path}
	for i: int in 6:
		registry["low_%d" % i] = path
	var sounds: Array[StringName] = []
	var prepared: Array[Node] = []
	var shown: Array[String] = []
	var manager := SafeAreaManager.new()
	manager.events.window_shown.connect(func(name: String, _window: Variant) -> void: shown.append(name))
	manager.configure(registry, func(cue: StringName) -> void: sounds.append(cue), func(node: Node) -> void:
		node.set_meta("prepared", true)
		prepared.append(node)
	)
	host.add_child(manager)
	var window := manager.show_ui("shared")
	_check(window != null and window.is_showing() and window.visible, "generic manager creates and shows scene")
	_check(window.get_meta("prepared", false) and prepared == [window], "host scene preparation runs once")
	_check(sounds == [UIBaseWindow.SOUND_WINDOW_OPEN], "host receives semantic open sound")
	(window.get_node("CloseBtn") as Button).button_down.emit()
	_check(sounds.back() == UIBaseWindow.SOUND_BUTTON_CLICK, "host receives semantic button sound")
	_check(manager.show_ui("shared") == window and prepared.size() == 1, "shown scene is reused")
	_check(manager.safe_area_calls == 2, "refreshing a shown scene reapplies current safe area")
	_check(shown == ["shared"] and manager._ordered_windows().count(window) == 1, "safe-area refresh neither republishes exposure nor duplicates the stack")

	var child_template := UIChildWindow.new()
	_add_button(child_template, "Action")
	var child_scene := PackedScene.new()
	_check(child_scene.pack(child_template) == OK, "pack child scene")
	child_template.free()
	var child := window.create_child(child_scene)
	_check(child != null and child.is_showing() and child.get_meta("prepared", false), "child inherits scene preparation")
	(child.get_node("Action") as Button).button_down.emit()
	_check(sounds.back() == UIBaseWindow.SOUND_BUTTON_CLICK and prepared.size() == 2, "child inherits host sound callback")

	# 同名窗口由不同 manager 管理；默认 CloseBtn 不能误关另一个 manager 的窗口。
	var other := UIWindowManager.new()
	other.configure({"shared": path})
	host.add_child(other)
	var other_window := other.show_ui("shared")
	(window.get_node("CloseBtn") as Button).pressed.emit()
	_check(window.is_hidden() and other_window.is_showing(), "close request routes to owning manager")
	(other_window.get_node("CloseBtn") as Button).button_down.emit()
	(other_window.get_node("CloseBtn") as Button).pressed.emit()
	_check(other_window.is_hidden(), "optional sound and scene callbacks can be omitted")

	# 层是逻辑优先级；反复打开低层也不能覆盖高层或其遮罩。
	manager.warm_pool("high")
	var high := manager.get_ui("high")
	_check(high.is_hidden() and not high.visible, "prewarmed scene stays hidden")
	high.ui_layer = UILayerConfig.LAYER_POPUP
	high.show_mask = true
	manager.show_ui("high")
	for i: int in 6:
		var low := manager.show_ui("low_%d" % i)
		_check(high.z_index > low.z_index + 126, "logical higher layer remains above window interior %d" % i)
	_check(_mask_z(host) == high.z_index - 1, "mask follows modal after lower-layer insertions")
	_check(high.get_index() > manager.get_ui("low_5").get_index(), "GUI tree order follows logical layers")
	manager.show_ui("low_5")
	_check(high.get_index() > manager.get_ui("low_5").get_index(), "refreshing already shown lower window preserves GUI order")
	var high_presses: Array[bool] = []
	(high.get_node("CloseBtn") as Button).pressed.connect(func() -> void: high_presses.append(true))
	await process_frame
	_send_mouse_button(true)
	_send_mouse_button(false)
	_check(high_presses.size() == 1 and high.is_hidden(), "actual GUI input reaches visually topmost modal")
	manager.show_ui("high")
	for i: int in 100:
		manager.hide_ui("low_0")
		manager.show_ui("low_0")
	_check(high.z_index <= 4095 and manager.get_ui("low_0").z_index < high.z_index, "reopening cannot exhaust z indices")

	manager.warm_pool("full")
	var full := manager.get_ui("full")
	full.is_fullscreen = true
	full.ui_layer = UILayerConfig.LAYER_MODAL
	manager.show_ui("full")
	_check(not high.visible and high.is_showing(), "occluded windows retain lifecycle state")
	manager.hide_ui("low_0")
	manager.show_ui("low_0")
	_check(not manager.get_ui("low_0").visible, "new lower window remains occluded by higher fullscreen window")
	manager.hide_all()
	_check(high.is_hidden() and full.is_hidden(), "hide_all includes occluded windows")
	_check(manager.get_window_count(UILayerConfig.LAYER_DEFAULT) == 0, "hide_all clears lower-layer stack")

	manager.show_ui("high")
	high.queue_free()
	await process_frame
	_check(manager.get_ui("high") == null and manager.get_window_count(UILayerConfig.LAYER_POPUP) == 0, "external window disposal clears cache and stack")
	_check(manager._modal_mask.request_count() == 0, "external modal disposal releases mask request")
	manager._on_back_button()
	manager.set_layer_visible(UILayerConfig.LAYER_POPUP, true)
	manager.warm_pool("high")
	_check(manager.get_ui("high") != null, "disposed window can be created again")

	manager.warm_pool_async("warm")
	var warm := manager.show_ui("warm")
	await process_frame
	await process_frame
	_check(manager.get_ui("warm") == warm and warm.is_showing(), "async prewarm cannot replace sync shown scene")
	var asynchronous := await manager.show_ui_async("async")
	_check(asynchronous != null and asynchronous.is_showing(), "real threaded scene loading works without product services")
	manager.hide_ui("warm")
	warm.queue_free()
	await process_frame
	manager.warm_pool("warm")
	_check(manager.get_ui("warm") != null and manager.get_ui("warm").is_hidden(), "prewarm recreates expired cache entry")

	# 管理器离树时停止异步后续；资源线程完成也不能重新生成窗口。
	var retiring := UIWindowManager.new()
	retiring.configure({"pending": path})
	host.add_child(retiring)
	retiring.warm_pool_async("pending")
	host.remove_child(retiring)
	await process_frame
	await process_frame
	_check(retiring.get_ui("pending") == null, "async prewarm cannot recreate windows after manager leaves tree")
	retiring.free()

	manager.queue_free()
	other.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(window) and not is_instance_valid(child), "manager disposal releases cached windows and children")
	_check(_mask_z(host) == -9999, "manager disposal releases modal masks")
	await _test_modal_consistency(host, path)
	await _test_occlusion_reentry(host, path)
	await _test_show_reentry(host, path)
	await _test_scene_disposal(host, path)
	await _test_callback_disposal(host, path)
	host.queue_free()
	await process_frame
	print("UI FRAMEWORK TESTS: %d assertions, %d failures%s" % [checks, failures, " (no Autoload)" if isolated else ""])
	quit(0 if failures == 0 else 1)


func _test_modal_consistency(host: Node, path: String) -> void:
	var manager := UIWindowManager.new()
	manager.configure({"a": path, "b": path, "full": path})
	host.add_child(manager)
	for name: String in ["a", "b", "full"]:
		manager.warm_pool(name)
	var a := manager.get_ui("a")
	var b := manager.get_ui("b")
	var full := manager.get_ui("full")
	a.show_mask = true
	a.mask_opacity = 0.25
	b.show_mask = true
	b.mask_opacity = 0.65
	b.is_fullscreen = true
	full.is_fullscreen = true
	full.ui_layer = UILayerConfig.LAYER_MODAL
	manager.show_ui("a")
	manager.show_ui("b")
	_check(not a.visible and _has_single_mask_below(host, b), "fullscreen modal covers lower modal")
	manager.hide_ui("b")
	_check(a.visible and _has_single_mask_below(host, a), "closing fullscreen modal restores lower modal and its mask")
	_check(manager._modal_mask.request_count() == 1, "fullscreen close retains exactly one modal request")
	manager.show_ui("b")
	b.queue_free()
	await process_frame
	await process_frame # tree_exiting 后的安全时点恢复遮罩节点顺序。
	_check(a.visible and _has_single_mask_below(host, a), "external fullscreen disposal restores lower modal mask")
	_check(manager._modal_mask.request_count() == 1, "external fullscreen disposal releases exactly its request")
	manager.show_ui("full")
	_check(not a.visible and _visible_masks(host).is_empty(), "nonmodal fullscreen leaves no mask belonging to covered windows")
	manager.hide_ui("full")
	_check(a.visible and _has_single_mask_below(host, a), "closing nonmodal fullscreen restores covered modal mask")
	manager.warm_pool("b")
	b = manager.get_ui("b")
	b.show_mask = true
	b.mask_opacity = 0.65
	manager.show_ui("b")
	manager.hide_ui("a")
	_check(_has_single_mask_below(host, b), "closing lower modal preserves upper modal mask")
	manager.hide_all()
	_check(_visible_masks(host).is_empty() and manager._modal_mask.request_count() == 0, "batch close balances all modal requests")

	# visible=false 的同步通知发生在 HIDDEN 与管理器出栈之间，仍属同一次打开。
	var events_seen: Array[String] = []
	manager.events.window_shown.connect(func(name: String, _window: Variant) -> void: events_seen.append("shown:" + name))
	manager.events.window_hidden.connect(func(name: String, _window: Variant) -> void: events_seen.append("hidden:" + name))
	var reopen := func() -> void:
		if a.is_hidden() and not a.visible:
			manager.show_ui("a")
	a.visibility_changed.connect(reopen)
	manager.show_ui("a")
	manager.hide_ui("a")
	_check(a.is_showing() and _has_single_mask_below(host, a), "visibility callback can reopen the same modal")
	_check(manager._modal_mask.request_count() == 1 and events_seen == ["shown:a"], "synchronous reopen retains one request and one shown event")
	a.visibility_changed.disconnect(reopen)
	manager.hide_ui("a")
	_check(manager._modal_mask.request_count() == 0 and _visible_masks(host).is_empty(), "later close releases synchronously reopened modal")
	_check(events_seen == ["shown:a", "hidden:a"], "synchronous reopen preserves shown and hidden pairing")

	b.is_fullscreen = true
	manager.show_ui("a")
	manager.show_ui("b")
	manager.hide_all_except(["a"])
	_check(a.is_showing() and a.visible and _has_single_mask_below(host, a), "hide_all_except restores the retained covered modal")
	manager.show_ui("b")
	# 批量关闭的首个回调可以直接释放另一窗口；后续快照项必须容忍缓存已删除。
	manager.events.window_hidden.connect(func(name: String, _window: Variant) -> void:
		if name == "a" and manager.get_ui("b") != null:
			manager.get_ui("b").free()
	)
	manager.hide_all()
	_check(manager.get_window_count(UILayerConfig.LAYER_DEFAULT) == 0 and manager._modal_mask.request_count() == 0, "batch close tolerates callback disposal of another cached modal")
	_check(_visible_masks(host).is_empty(), "batch close with callback disposal leaves no mask")
	manager.queue_free()
	await process_frame
	await process_frame


func _test_occlusion_reentry(host: Node, path: String) -> void:
	for action: String in ["close_cover", "destroy_target", "destroy_cover", "close_from_hook"]:
		var manager := UIWindowManager.new()
		manager.configure({"a": path, "b": path, "c": path})
		host.add_child(manager)
		for name: String in ["a", "b", "c"]:
			var window := OcclusionWindow.new()
			window._ui_name = name
			window.tree_exiting.connect(manager._on_window_exiting.bind(name, window))
			host.add_child(window)
			manager._cache[name] = window
			window._do_create()
		var a := manager.get_ui("a") as OcclusionWindow
		var b := manager.get_ui("b") as OcclusionWindow
		var c := manager.get_ui("c") as OcclusionWindow
		c.is_fullscreen = true
		c.show_mask = true
		manager.show_ui("a")
		manager.show_ui("b")
		var hooks: Array[String] = b.stack_events
		var acted := {"done": false}
		var on_covered := func() -> void:
			if acted.done or b.visible:
				return
			acted.done = true
			match action:
				"close_cover": manager.hide_ui("c")
				"destroy_target": b.queue_free()
				"destroy_cover": manager.get_ui("c").free()
		if action == "close_from_hook":
			b.bottom_action = func() -> void: manager.hide_ui("c")
		else:
			b.visibility_changed.connect(on_covered)
		manager.show_ui("c")
		if action == "destroy_target":
			_check(manager.get_ui("b") == null and hooks.is_empty(), "occlusion skips a destroyed target's old stack hook")
			_check(not a.visible and c.visible, "destroying a covered target retains the fullscreen cover")
		else:
			_check(a.is_showing() and a.visible and b.is_showing() and b.visible, action + " restarts occlusion from the current stack")
			_check(manager._ordered_windows() == [a, b], action + " leaves exactly the surviving windows stacked")
			_check(manager._modal_mask.request_count() == 0 and _visible_masks(host).is_empty(), action + " balances the interrupted cover's modal request")
			_check(hooks == (["bottom", "top"] if action == "close_from_hook" else ["top"]), action + " only publishes current stack hooks")
		manager.queue_free()
		await process_frame
		await process_frame
	for action: String in ["reopen", "destroy"]:
		var manager := UIWindowManager.new()
		manager.configure({"a": path, "c": path})
		host.add_child(manager)
		manager.warm_pool("c")
		var a := manager.show_ui("a")
		var c := manager.get_ui("c")
		c.is_fullscreen = true
		c.show_mask = true
		var events_seen: Array[String] = []
		manager.events.window_shown.connect(func(name: String, _win: Variant) -> void: events_seen.append("shown:" + name))
		manager.events.window_hidden.connect(func(name: String, _win: Variant) -> void: events_seen.append("hidden:" + name))
		manager.show_ui("c")
		var acted := {"done": false}
		a.visibility_changed.connect(func() -> void:
			if not a.visible or acted.done:
				return
			acted.done = true
			if action == "reopen":
				manager.show_ui("c")
			else:
				manager.get_ui("c").free()
		)
		manager.hide_ui("c")
		if action == "reopen":
			_check(c.is_showing() and c.visible and not a.visible, "restoring a lower window can reopen the old cover without stale hide completion")
			_check(manager._modal_mask.request_count() == 1 and events_seen == ["shown:c"], "restoration reopen preserves one modal request and exposure")
			manager.hide_ui("c")
		else:
			_check(manager.get_ui("c") == null and a.visible, "restoration callback can destroy the retiring cover")
		_check(manager._modal_mask.request_count() == 0 and events_seen == ["shown:c", "hidden:c"], action + " during restoration eventually balances modal requests and exposure")
		_check(manager._ordered_windows() == [a] and manager._announced_windows.size() == 1, action + " during restoration leaves no stale cover ownership")
		manager.queue_free()
		await process_frame
		await process_frame


func _test_show_reentry(host: Node, path: String) -> void:
	var manager := UIWindowManager.new()
	manager.configure({"immediate": path, "ordinary": path})
	host.add_child(manager)
	var window := ImmediateCloseWindow.new()
	window.show_mask = true
	window._ui_name = "immediate"
	window.close_requested.connect(manager.hide_ui.bind("immediate"))
	window.tree_exiting.connect(manager._on_window_exiting.bind("immediate", window))
	host.add_child(window)
	manager._cache["immediate"] = window
	window._do_create()
	var observed: Array[String] = []
	var cancelled: Array[String] = []
	manager.events.window_shown.connect(func(name: String, _window: Variant) -> void: observed.append("shown:" + name))
	manager.events.window_hidden.connect(func(name: String, _window: Variant) -> void: observed.append("hidden:" + name))
	manager.events.window_show_cancelled.connect(func(name: String, _window: Variant) -> void: cancelled.append(name))
	manager.show_ui("immediate")
	_check(window.is_hidden() and not window.visible and window.open_animation_calls == 0, "on_show can cancel without starting the opening animation")
	_check(observed.is_empty() and manager._modal_mask.request_count() == 0, "cancelled on_show publishes no unmatched events or mask")
	_check(cancelled == ["immediate"] and manager._ordered_windows().is_empty(), "cancelled display publishes its distinct completion after unstacking")

	window.close_on_show = false
	var close_when_shown := func(name: String, _window: Variant) -> void:
		if name == "immediate":
			manager.hide_ui(name)
	manager.events.window_shown.connect(close_when_shown)
	manager.show_ui("immediate")
	manager.events.window_shown.disconnect(close_when_shown)
	_check(observed == ["shown:immediate", "hidden:immediate"] and window.is_hidden(), "shown listener can close with ordered paired events")
	_check(cancelled == ["immediate"], "ordinary shown/hidden lifecycle does not publish a second cancellation")
	_check(manager._modal_mask.request_count() == 0, "shown listener close releases the modal request")

	observed.clear()
	var reopened := {"done": false}
	var reopen_when_shown := func(name: String, _window: Variant) -> void:
		if name == "immediate" and not reopened.done:
			reopened.done = true
			manager.hide_ui(name)
			manager.show_ui(name)
	manager.events.window_shown.connect(reopen_when_shown)
	manager.show_ui("immediate")
	manager.events.window_shown.disconnect(reopen_when_shown)
	_check(observed == ["shown:immediate", "hidden:immediate", "shown:immediate"] and window.is_showing(), "shown listener can close and reopen a new display")
	_check(manager._modal_mask.request_count() == 1, "synchronous close and reopen retains one modal request")
	manager.hide_ui("immediate")
	_check(observed.back() == "hidden:immediate" and manager._announced_windows.is_empty(), "final close balances reentrant display events")

	observed.clear()
	manager.warm_pool("ordinary")
	manager.get_ui("ordinary").show_mask = true
	var dispose_when_shown := func(name: String, shown: UIFrameWindow) -> void:
		if name == "ordinary":
			shown.free()
	manager.events.window_shown.connect(dispose_when_shown)
	var disposed := manager.show_ui("ordinary")
	_check(disposed == null and manager.get_ui("ordinary") == null, "shown listener disposal returns no freed window")
	_check(observed == ["shown:ordinary", "hidden:ordinary"] and manager._modal_mask.request_count() == 0, "shown listener disposal balances events and masks")
	manager.queue_free()
	await process_frame
	await process_frame


func _test_callback_disposal(host: Node, path: String) -> void:
	var manager := UIWindowManager.new()
	manager.configure({"created": path, "managed": path})
	host.add_child(manager)
	var dispose_created := func(_name: String, window: UIFrameWindow) -> void: window.free()
	manager.events.window_created.connect(dispose_created)
	var created := manager.show_ui("created")
	_check(created == null and manager.get_ui("created") == null, "creation listener disposal returns no stale instance")
	manager.events.window_created.disconnect(dispose_created)
	var managed := manager.show_ui("managed")
	var source := Node.new()
	host.add_child(source)
	managed.connect_managed(source.renamed, func() -> void: pass)
	source.free()
	manager.hide_ui("managed")
	_check(managed.is_hidden() and managed._managed_connections.is_empty(), "managed signal cleanup tolerates source destruction before its window")
	manager.block_input_briefly(managed, 0.05)
	manager.block_input_briefly(managed, 0.05)
	manager.block_input_briefly(managed, 0.05)
	var blockers: int = 0
	for node: Node in managed.get_children():
		if node.name == &"_InputBlocker":
			blockers += 1
	_check(blockers == 1 and managed.get_child_count() == 2, "repeated input blocking replaces its prior control instead of accumulating renamed blockers")
	managed.free()
	await create_timer(0.1).timeout
	_check(manager.get_ui("managed") == null, "input-block timers safely finish after their target is freed")
	manager.queue_free()
	await process_frame
	await process_frame


func _test_frame_creation(host: Node) -> void:
	var fixture = load("res://tools/validation/fixtures/ui_creating_frame.gd")
	for stage: String in ["preparer", "ready", "visibility_create", "create"]:
		for action: String in ["reenter", "close", "queue_free", "destroy"]:
			var node = fixture.new()
			node.trigger_stage = stage
			node.action = action
			var packed := PackedScene.new()
			_check(packed.pack(node) == OK, "pack frame creation fixture")
			node.free()
			var path: String = "res://frame_%s_%s.tscn" % [stage, action]
			_check(ResourceSaver.save(packed, path) == OK, "save frame creation fixture")
			var manager := UIWindowManager.new()
			var observations: Array = []
			var prepared := {"count": 0}
			var shown: Array = []
			manager.set_meta("observations", observations)
			var hooks: Array = []
			manager.set_meta("created_hooks", hooks)
			manager.configure({"frame": path}, Callable(), func(win: Node) -> void:
				prepared.count += 1
				win.set_meta("manager", manager)
				if stage == "preparer":
					win._act(stage))
			manager.events.window_shown.connect(func(_name: String, win: UIFrameWindow) -> void: shown.append(win))
			host.add_child(manager)
			var returned := manager.show_ui("frame")
			var label: String = stage + "/" + action
			if action == "reenter":
				_check(prepared.count == 1 and observations == [null], label + " rejects half-created synchronous lookup without a duplicate")
				_check(returned != null and returned.is_showing() and manager._ordered_windows().size() == 1 and shown.size() == 1, label + " outer caller publishes one ready instance")
			else:
				_check(returned == null and manager.get_ui("frame") == null and manager._ordered_windows().is_empty(), label + " cancelled creation cannot return or stack an instance")
				_check(shown.is_empty(), label + " cancelled creation publishes no shown event")
				if stage != "create":
					_check(hooks.is_empty(), label + " cancellation does not run the later create hook")
			_check(manager._creating.is_empty(), label + " creation reservation is released")
			manager.queue_free()
			await process_frame
	# 宿主预处理可直接释放节点；旧引用不能越过回调边界。
	for stage: String in ["preparer"]:
		var node = fixture.new()
		node.trigger_stage = stage
		node.action = "free"
		var packed := PackedScene.new()
		packed.pack(node)
		node.free()
		var path: String = "res://frame_%s_free.tscn" % stage
		ResourceSaver.save(packed, path)
		var manager := UIWindowManager.new()
		manager.set_meta("observations", [])
		manager.configure({"frame": path}, Callable(), func(win: Node) -> void:
			win.set_meta("manager", manager)
			if stage == "preparer": win.free())
		host.add_child(manager)
		_check(await manager.show_ui_async("frame") == null and manager._creating.is_empty(), stage + " direct free cancels asynchronous creation without recreating")
		manager.queue_free()
		await process_frame


func _test_child_creation(host: Node) -> void:
	var script: Script = load("res://tools/validation/fixtures/ui_creating_child.gd")
	for stage: String in ["ready", "create", "show", "visibility_create", "visibility_show"]:
		for action: String in ["close", "destroy_owner", "queue_free"]:
			var parent := DestroyParent.new()
			parent.set_meta("creation_events", parent.events)
			host.add_child(parent)
			parent._do_create()
			parent._do_show()
			var template: UIChildWindow = script.new()
			template.set("stage", stage)
			template.set("action", action)
			var packed := PackedScene.new()
			_check(packed.pack(template) == OK, "pack creation callback fixture")
			template.free()
			var returned := parent.create_child(packed)
			_check(returned == null and parent._managed_children.is_empty(), stage + "/" + action + " leaves no returned or managed child")
			_check(parent.events.count("child_destroy") == 1, stage + "/" + action + " destroys child exactly once")
			if stage != "show":
				_check(not parent.events.has("show"), stage + "/" + action + " never resumes creation into show")
			if stage in ["ready", "visibility_create"]:
				_check(not parent.events.has("create"), stage + "/" + action + " never calls create after cancellation")
			parent.queue_free()
			await process_frame

	# 资源准备可以直接释放尚未运行的节点；创建者不能访问它或留下失效托管记录。
	var parent := DestroyParent.new()
	parent.set_meta("creation_events", parent.events)
	host.add_child(parent)
	parent._do_create()
	parent.configure_ui(Callable(), func(node: Node) -> void: node.free())
	var template := UIChildWindow.new()
	var packed := PackedScene.new()
	packed.pack(template)
	template.free()
	_check(parent.create_child(packed) == null and parent._managed_children.is_empty(), "direct free inside scene preparation safely ends creation")
	parent.queue_free()
	await process_frame

	# 关闭动画仍允许等待；create_child 不把正在退场的窗口交给调用者继续装配。
	parent = DestroyParent.new()
	parent.set_meta("creation_events", parent.events)
	host.add_child(parent)
	parent._do_create()
	template = script.new()
	template.set("delayed_hide", true)
	packed = PackedScene.new()
	packed.pack(template)
	template.free()
	_check(parent.create_child(packed) == null and parent._managed_children.size() == 1, "asynchronous self-close retains ownership only until hide finishes")
	var closing: UIChildWindow = parent._managed_children[0]
	closing.emit_signal("finish_hide")
	_check(parent._managed_children.is_empty() and closing.is_queued_for_deletion(), "self-close completion unregisters and frees child")
	parent.queue_free()
	await process_frame

	# 资源准备回调也在所有权建立之后执行，即使节点尚未进树。
	parent = DestroyParent.new()
	parent.set_meta("creation_events", parent.events)
	host.add_child(parent)
	parent._do_create()
	parent.configure_ui(Callable(), func(node: Node) -> void: parent.destroy_child(node))
	template = UIChildWindow.new()
	packed = PackedScene.new()
	packed.pack(template)
	template.free()
	_check(parent.create_child(packed) == null and parent._managed_children.is_empty(), "scene preparer may cancel before ready without resurrecting the node")
	parent.queue_free()
	await process_frame


func _test_child_teardown(host: Node) -> void:
	var parent := DestroyParent.new()
	host.add_child(parent)
	parent._do_create()
	var child := _delayed_child(parent)
	parent.destroy_child(child)
	parent.destroy_child(child)
	_check(child.hide_calls == 1 and parent.events.is_empty(), "duplicate child close waits on only one hide")
	parent._do_destroy()
	_check(parent.events == ["child", "parent"], "parent disposal synchronously destroys children before its own hook")
	_check(parent._managed_children.is_empty() and child.get_window_state() == UIBaseWindow.WindowState.DESTROYED, "forced child teardown clears ownership and invalidates waits")
	child.released.emit()
	_check(parent.events == ["child", "parent"], "old child hide completion cannot destroy twice")
	parent._do_destroy()
	_check(parent.events.size() == 2, "owner destruction is idempotent")
	parent.queue_free()
	await process_frame

	parent = DestroyParent.new()
	host.add_child(parent)
	parent._do_create()
	child = _delayed_child(parent)
	parent.destroy_child(child)
	child._do_show()
	child.released.emit()
	_check(child.is_showing() and child in parent._managed_children and parent.events.is_empty(), "reopened child survives an obsolete graceful close")
	parent.destroy_child(child)
	child.released.emit()
	_check(parent.events == ["child"] and parent._managed_children.is_empty(), "current graceful close destroys and unregisters child")
	parent.queue_free()
	await process_frame

	parent = DestroyParent.new()
	host.add_child(parent)
	parent._do_create()
	child = _delayed_child(parent)
	parent.destroy_all_children()
	_check(parent.events == ["child"] and child.hide_calls == 0, "bulk teardown completes synchronously without starting hide animations")
	_check(parent.get_window_state() != UIBaseWindow.WindowState.DESTROYED, "bulk child teardown does not destroy its owner")
	parent.queue_free()
	await process_frame


func _delayed_child(parent: DestroyParent) -> DelayedChild:
	var child := DelayedChild.new()
	parent.add_child(child)
	child.events = parent.events
	child._do_create()
	child._do_show()
	# 与 create_child 完成后的所有权相同；测试子类提供可控退场信号。
	parent._managed_children.append(child)
	return child


func _visible_masks(host: Node) -> Array[ColorRect]:
	var masks: Array[ColorRect] = []
	for node: Node in host.get_children():
		if node is ColorRect and String(node.name).begins_with("_GlobalMask") and node.visible:
			masks.append(node as ColorRect)
	return masks


func _test_scene_disposal(previous_scene: Node, path: String) -> void:
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var manager := UIWindowManager.new()
	manager.configure({"modal": path})
	root.add_child(manager)
	manager.warm_pool("modal")
	manager.get_ui("modal").show_mask = true
	manager.show_ui("modal")
	scene.queue_free()
	await process_frame
	await process_frame
	_check(manager.get_ui("modal") == null and manager._modal_mask.request_count() == 0, "scene disposal cleans windows and masks while manager survives")
	current_scene = previous_scene
	manager.queue_free()
	await process_frame
	_check(not is_instance_valid(manager), "manager may safely exit after its scene-owned mask was already freed")


func _has_single_mask_below(host: Node, window: UIFrameWindow) -> bool:
	var masks := _visible_masks(host)
	return masks.size() == 1 and masks[0].z_index == window.z_index - 1 \
		and masks[0].get_index() < window.get_index() \
		and is_equal_approx(masks[0].color.a, window.mask_opacity)


func _add_button(parent: Node, button_name: String) -> void:
	var button := Button.new()
	button.name = button_name
	button.size = Vector2(60, 60)
	parent.add_child(button)
	button.owner = parent


func _send_mouse_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(10, 10)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	# 使用 Viewport 逻辑坐标，避免产品的 canvas_items 拉伸把 10px 再换算一次。
	root.push_input(event, true)


func _mask_z(host: Node) -> int:
	for node: Node in host.get_children():
		if node is ColorRect and String(node.name).begins_with("_GlobalMask"):
			return (node as ColorRect).z_index
	return -9999


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
