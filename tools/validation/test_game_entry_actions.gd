## 真实缓存页面在入场失败、准备及关闭后，不得通过透明按钮或迟到动作扣费建局。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node
var state: Node
var files: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	ui = root.get_node("UIManager")
	state = root.get_node("GameState")
	files = state.get_core_store().get("_file_store")
	var ab: Node = root.get_node("ABTestManager")
	state.set_sound_on(false)
	state.set_tutorial_done(true)
	state.set_current_level(50)
	state.set_tool_count("hint", 10)
	ab.daily_first_level_difficulty.set_debug_override(0)
	ab.normal_endgame_save.set_debug_override(0)
	ab.dc_level.set_debug_override(0)

	# 首次准备失败时，空棋盘也不得建立临时业务 Session。
	ContentContext.report_content_error("doku/levels/test", "test_entry_read_failed")
	var page: Variant = ui.show_ui("game", {"level_index": 50})
	await process_frame
	await _assert_blocked(page, "first failed entry")
	await _close("game")
	ContentContext.publish(null)

	# 正常重试必须仍然可用；实际鼠标点击成功消费提示，并形成真实可复用缓存页。
	page = ui.show_ui("game", {"level_index": 50})
	await _wait_ready(page)
	_check(page._is_round_entry_ready(), "normal main retry commits entry")
	var before_hint: int = state.get_tool_count("hint")
	await _click_hint(page)
	_check(state.get_tool_count("hint") == before_hint - 1, "real hint click works after successful entry")
	_check(state.get_core_store().snapshot().round_services.has("doku/main"), "normal hint establishes a durable main round")
	await _close("game")
	_check(page._execute_business_action("request_hint").get("error") == "entry_not_ready", "closed page rejects delayed business actions")

	ContentContext.report_content_error("doku/levels/test", "test_entry_read_failed")
	page = ui.show_ui("game", {"level_index": 50})
	await process_frame
	_check(not page._board_view.get_board().is_empty(), "cached failure fixture retains previous board")
	_check(not page._entry_error.is_empty() and page._entry_preparing, "cached entry remains failed")
	await _assert_blocked(page, "cached content failure")
	await _close("game")
	ContentContext.publish(null)

	# 保存失败与内容失败使用相同的业务门槛；准备尚未结束时也没有可调用窗口。
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page = ui.show_ui("game", {"level_index": 50})
	await create_timer(0.1).timeout
	_check(not page._entry_error.is_empty(), "main entry commit failure is observed")
	await _assert_blocked(page, "main commit failure")
	files.set_fault_injector_for_tests(Callable())
	await _close("game")
	page = ui.show_ui("game", {"level_index": 50})
	_check(page._ensure_business_round().get("error") == "entry_not_ready", "layout preparation cannot establish a round")
	ui.hide_ui("game")
	await create_timer(0.2).timeout
	_check(not page._entry_ready, "cancelled main preparation cannot become ready later")

	# 提交通知允许同步离页；已完成落盘也不能让旧入口重新变成可操作。
	page = ui.show_ui("game", {"level_index": 50})
	var leave_on_commit := func(_revision: int) -> void: ui.hide_ui("game")
	state.get_core_store().committed.connect(leave_on_commit, CONNECT_ONE_SHOT)
	await create_timer(0.2).timeout
	_check(page.is_hidden() and not page._entry_ready, "commit observer closing main leaves entry invalid")
	if state.get_core_store().committed.is_connected(leave_on_commit):
		state.get_core_store().committed.disconnect(leave_on_commit)

	# 每日复用同一门槛，正常准备成功后可建立业务局，缓存失败后再次拒绝。
	var daily: Variant = ui.show_ui("daily_game")
	await _wait_ready(daily)
	_check(daily._is_round_entry_ready(), "daily entry becomes ready after commit")
	_check(daily._ensure_business_round().get("ok", false), "normal daily supports business round")
	await _close("daily_game")
	ContentContext.report_content_error("doku/levels/test", "test_entry_read_failed")
	daily = ui.show_ui("daily_game")
	await process_frame
	await _assert_blocked(daily, "daily content failure")
	await _close("daily_game")
	ContentContext.publish(null)
	daily = ui.show_ui("daily_game")
	ui.hide_ui("daily_game")
	await create_timer(0.2).timeout
	_check(not daily._entry_ready, "cancelled daily preparation cannot become ready later")

	ui.hide_all()
	host.queue_free()
	await process_frame
	await process_frame
	print("GAME ENTRY ACTION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _assert_blocked(page: Variant, label: String) -> void:
	var before: Dictionary = state.get_core_store().snapshot()
	_check(not page._entry_ready, label + " is not business ready")
	_check(page._clock_timer.is_stopped() and not page._board_view.visible, label + " stops clock and hides board")
	page._on_appear_animation_finished()
	_check(page._entry_anim_playing and page._board_view.mouse_filter == Control.MOUSE_FILTER_IGNORE, label + " old animation completion cannot unlock")
	# 即使表现层误把动画标志清除，业务门槛仍独立生效。
	page._entry_anim_playing = false
	await _click_hint(page)
	var rejected: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(rejected.get("error") == "entry_not_ready", label + " direct action rejects before creating session")
	_check(page._business_session == null, label + " does not create a session")
	var after: Dictionary = state.get_core_store().snapshot()
	_check(after.inventory == before.inventory and after.round_services == before.round_services, label + " input cannot debit inventory or alter rounds")
	page._entry_anim_playing = true


func _click_hint(page: Variant) -> void:
	var hit: Control = page._tool_hint_btn.get_node("Hit")
	var pos: Vector2 = hit.get_global_transform_with_canvas() * (hit.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._entry_ready and not page._entry_anim_playing, "entry and animation complete before normal input")


func _close(name: String) -> void:
	ui.hide_ui(name)
	await create_timer(0.1).timeout


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + label)
