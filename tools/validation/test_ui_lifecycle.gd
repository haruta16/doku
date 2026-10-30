## 受控等待验证真实 UIManager 的重入：旧关闭与异步预热不能影响新显示。
extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	# This suite owns UI timing; audio playback/cleanup is covered by the audio lifecycle suite.
	root.get_node("GameState").set_sound_on(false)
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var manager: Variant = load("res://tools/validation/fixtures/ui_lifecycle_manager.gd").new()
	host.add_child(manager)
	var hidden: Array[String] = []
	manager.events.window_hidden.connect(func(name: String, _window: Variant) -> void: hidden.append(name))

	# 同一实例经历 show/hide/show/hide，第一次关闭比第二次先结束。
	var closing: Variant = manager.new_window()
	closing.show_mask = true
	_register(manager, host, "closing", closing)
	manager.show_ui("closing")
	manager.hide_ui("closing")
	manager.show_ui("closing")
	manager.hide_ui("closing")
	_check(closing.close_gates.size() == 2, "two independent close waits exist")
	closing.close_gates[0].released.emit()
	_check(closing.visible and closing.get_window_state() == closing.WindowState.CLOSING, "old animation completion leaves new closing instance visible")
	_check(closing.hide_calls == 0 and hidden.is_empty(), "old close cannot call on_hide or publish hidden")
	_check(manager._modal_mask.request_count() == 1, "old close cannot release current mask")
	closing.close_gates[1].released.emit()
	_check(closing.is_hidden() and not closing.visible and closing.hide_calls == 1, "current close finishes exactly once")
	_check(hidden == ["closing"] and manager._modal_mask.request_count() == 0, "current close balances mask and hidden event")

	# on_hide 自己也可能等待；两次返回时状态都为 CLOSING，仅检查枚举不够。
	var hiding: Variant = manager.new_window()
	hiding.delay_close = false
	hiding.delay_hide = true
	hiding.dialog_name = "hiding_dialog"
	var tracker: Node = root.get_node("Tracker")
	tracker._source_stack.assign(["base_screen"])
	_register(manager, host, "hiding", hiding)
	manager.show_ui("hiding")
	manager.hide_ui("hiding")
	_check(tracker.get_current_source() == "hiding_dialog", "pending on_hide retains dialog source")
	manager.show_ui("hiding")
	manager.hide_ui("hiding")
	_check(hiding.hide_gates.size() == 2, "two on_hide waits exist")
	hiding.hide_gates[0].released.emit()
	_check(hiding.visible and hiding.get_window_state() == hiding.WindowState.CLOSING, "old on_hide does not hide reused window")
	_check(hidden == ["closing"], "old on_hide does not remove current stack entry")
	_check(tracker.get_current_source() == "hiding_dialog", "aborted hide retains source for reused dialog")
	# 关闭可见性回调中出现的新弹窗，不能被旧弹窗收尾移除。
	var next_dialog: Variant = manager.new_window()
	next_dialog.delay_close = false
	next_dialog.dialog_name = "next_dialog"
	_register(manager, host, "next_dialog", next_dialog)
	hiding.visibility_changed.connect(func() -> void:
		if not hiding.visible:
			manager.show_ui("next_dialog")
	)
	hiding.hide_gates[1].released.emit()
	_check(hiding.is_hidden() and not hiding.visible and hidden == ["closing", "hiding"], "current on_hide remains hidden when visibility callback opens another dialog")
	_check(tracker.get_current_source() == "next_dialog", "closing old dialog preserves newer source")
	manager.hide_ui("next_dialog")
	_check(tracker.get_current_source() == "base_screen", "dialog source balances after actual closes")
	var source_at_hidden: Array[String] = []
	manager.events.window_hidden.connect(func(_name: String, _window: Variant) -> void:
		source_at_hidden.append(tracker.get_current_source())
	)
	manager.show_ui("next_dialog")
	manager.hide_ui("next_dialog")
	_check(source_at_hidden == ["base_screen"], "tracker source is settled before external hidden listeners")

	# 同一弹窗在 HIDDEN 的同步可见性通知里重开，产品曝光与来源也必须成对。
	var reopened: Variant = manager.new_window()
	reopened.delay_close = false
	reopened.show_mask = true
	reopened.dialog_name = "reopened_dialog"
	_register(manager, host, "reopened", reopened)
	var reopened_shown: Array[String] = []
	manager.events.window_shown.connect(func(name: String, _window: Variant) -> void:
		if name == "reopened":
			reopened_shown.append(name)
	)
	var reopen_same := func() -> void:
		if reopened.is_hidden() and not reopened.visible:
			manager.show_ui("reopened")
	reopened.visibility_changed.connect(reopen_same)
	manager.show_ui("reopened")
	manager.hide_ui("reopened")
	_check(reopened.is_showing() and reopened_shown == ["reopened"], "visibility reopen does not publish duplicate product exposure")
	_check(tracker.get_current_source() == "reopened_dialog" and manager._modal_mask.request_count() == 1, "visibility reopen retains dialog source and one modal request")
	reopened.visibility_changed.disconnect(reopen_same)
	manager.hide_ui("reopened")
	_check(hidden.count("reopened") == 1 and manager._modal_mask.request_count() == 0, "reopened product dialog closes exactly once")
	_check(tracker.get_current_source() == "base_screen", "reopened product dialog releases tracker source on final close")

	# 两层模态交接与打断：遮罩数量、透明度和层级均从实际节点观测。
	var lower: Variant = manager.new_window()
	lower.show_mask = true
	lower.mask_opacity = 0.25
	_register(manager, host, "mask_lower", lower)
	var upper: Variant = manager.new_window()
	upper.show_mask = true
	upper.mask_opacity = 0.65
	upper.hide_duration = 0.2
	_register(manager, host, "mask_upper", upper)
	manager.show_ui("mask_lower")
	manager.show_ui("mask_upper")
	_check(_has_single_mask_below(host, upper), "one mask follows top modal opacity and layer")
	manager.hide_ui("mask_upper")
	_check(_visible_masks(host).size() == 2 and manager._modal_mask.request_count() == 2, "modal close crossfades without releasing request early")
	manager.show_ui("mask_upper")
	_check(_has_single_mask_below(host, upper) and manager._modal_mask.request_count() == 2, "reopen collapses crossfade and restores top modal mask")
	upper.close_gates[0].released.emit()
	_check(upper.is_showing() and _has_single_mask_below(host, upper), "interrupted close cannot disturb reopened modal")
	upper.hide_duration = 0.0
	manager.hide_ui("mask_upper")
	upper.close_gates[1].released.emit()
	_check(_has_single_mask_below(host, lower) and manager._modal_mask.request_count() == 1, "instant close hands mask to remaining modal")
	lower.hide_duration = 0.02
	manager.hide_ui("mask_lower")
	lower.close_gates[0].released.emit()
	_check(manager._modal_mask.request_count() == 0, "last modal releases request after actual close")
	await create_timer(0.06).timeout
	await process_frame # 离开 timeout 回调，等待本帧 Tween 收尾。
	_check(_visible_masks(host).is_empty(), "last modal fade ends without a visible mask")

	# 真实同步创建与受控异步加载交错，不依赖线程或机器速度制造竞争。
	var template: Variant = load("res://scripts/framework/ui/base/ui_frame_window.gd").new()
	manager.packed_fixture = PackedScene.new()
	_check(manager.packed_fixture.pack(template) == OK, "pack fixture")
	template.free()
	var fixture_path: String = "res://ui_lifecycle_fixture.tscn"
	_check(ResourceSaver.save(manager.packed_fixture, fixture_path) == OK, "write fixture only in isolated project")
	manager._registry["warm"] = fixture_path
	var created: Array[String] = []
	manager.events.window_created.connect(func(name: String, _window: Variant) -> void: created.append(name))
	manager.warm_pool_async("warm")
	var shown: Variant = manager.show_ui("warm")
	manager.load_ready.emit()
	_check(manager.get_ui("warm") == shown and shown.is_showing() and shown.visible, "late warmup retains synchronously shown instance")
	_check(created.count("warm") == 1, "warmup creates no orphan duplicate")
	manager.hide_ui("warm")
	manager._registry["async"] = fixture_path
	var async_result: Array = []
	_show_async(manager, async_result)
	var sync_result: Variant = manager.show_ui("async")
	manager.load_ready.emit()
	_check(async_result.size() == 1 and async_result[0] == sync_result, "async show reuses simultaneous synchronous instance")
	_check(created.count("async") == 1, "simultaneous shows create only one cached window")
	manager.hide_ui("async")
	# window_created 是同步通知；监听者可直接显示预热产生的窗口。
	manager.events.window_created.connect(func(name: String, _window: Variant) -> void:
		if name.begins_with("created_"):
			manager.show_ui(name)
	)
	for name: String in ["created_sync", "created_async"]:
		manager._registry[name] = fixture_path
		if name == "created_sync":
			manager.warm_pool(name)
		else:
			manager.warm_pool_async(name)
			manager.load_ready.emit()
		var opened: Variant = manager.get_ui(name)
		_check(opened.is_showing() and opened.visible, "warmup preserves show from created callback: " + name)
		manager.hide_ui(name)
	# 动态控件走注入的产品准备端口，不能遗漏 1.22 的跨弹窗按键保护。
	var dynamic_owner: Variant = manager.show_ui("warm")
	var dynamic_button := Button.new()
	dynamic_owner.add_child(dynamic_button)
	dynamic_owner.initialize_dynamic_widget(dynamic_button)
	dynamic_owner.initialize_dynamic_widget(dynamic_button)
	dynamic_button.button_down.emit()
	_check(manager._guard_held_buttons.count(dynamic_button) == 1, "dynamic button guard is installed once through framework injection")
	dynamic_button.button_up.emit()
	_check(not manager._guard_held_buttons.has(dynamic_button), "dynamic button release clears its held ownership")
	manager.hide_ui("warm")
	manager.queue_free()
	await process_frame
	await process_frame
	_check(_mask_nodes(host).is_empty(), "manager disposal removes owned mask nodes")
	host.queue_free()
	await process_frame
	await process_frame
	print("UI LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _register(manager: Node, host: Node, name: String, window: Variant) -> void:
	manager._registry[name] = "fixture"
	window._ui_name = name
	host.add_child(window)
	window._do_create()
	manager._cache[name] = window


func _show_async(manager: Node, results: Array) -> void:
	results.append(await manager.show_ui_async("async"))


func _mask_nodes(host: Node) -> Array[ColorRect]:
	var masks: Array[ColorRect] = []
	for child: Node in host.get_children():
		if child is ColorRect and String(child.name).begins_with("_GlobalMask"):
			masks.append(child as ColorRect)
	return masks


func _visible_masks(host: Node) -> Array[ColorRect]:
	var masks: Array[ColorRect] = []
	for mask: ColorRect in _mask_nodes(host):
		if mask.visible:
			masks.append(mask)
	return masks


func _has_single_mask_below(host: Node, window: Variant) -> bool:
	var masks: Array[ColorRect] = _visible_masks(host)
	return masks.size() == 1 and masks[0].z_index == window.z_index - 1 \
		and masks[0].get_index() < window.get_index() \
		and is_equal_approx(masks[0].color.a, window.mask_opacity)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
