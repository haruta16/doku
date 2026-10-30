## AB 生命预警：真实错标后退出、重开、销毁，不得消费旧页面输入或一次性资格。
extends SceneTree
var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	ab.draft_mode.set_debug_override(5)
	ab.auto_x_fill_mode.set_debug_override(0)
	for transition: String in ["back", "reopen", "destroy"]:
		await _test_cancelled_warning(transition)
	await _test_current_warning()
	await _test_covered_warning()
	for mode: String in ["game", "daily_game"]:
		for kind: String in ["guess", "draft"]:
			await _test_covered_error_timers(mode, kind)
			await _test_revived_error_timers(mode, kind)
	for kind: String in ["guess", "draft"]:
		for transition: String in ["hide", "reopen"]:
			await _test_cancelled_error_timers(kind, transition)
	ui.hide_all()
	await create_timer(0.5).timeout
	print("GAME WARNING LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open(mode: String = "game") -> Variant:
	ui.hide_all()
	await create_timer(0.1).timeout
	_check(game.reset_all(), "isolated state reset")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("draft", 5)
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing or page._tool_btns_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._is_round_entry_ready(), "actual page ready")
	return page


func _test_cancelled_warning(transition: String) -> void:
	var page: Variant = await _open()
	page._lives = 2
	page._on_wrong_guess(0, 0)
	_check(page._lives == 1, "actual wrong move schedules warning at one life")
	if transition == "back":
		page._on_gear_btn_pressed()
	elif transition == "reopen":
		ui.hide_ui("game")
		ui.show_ui("game", {"level_index": 50})
	else:
		page._do_destroy()
		page.queue_free()
	await create_timer(1.9).timeout
	_check(not game.has_shown_warn_life(), "cancelled " + transition + " cannot consume once-only warning flag")
	if transition != "destroy":
		_check(page._warn_phase == 0 and not page._warn_click_allowed, "old delay cannot activate warning on hidden/reused page")
		if transition == "back":
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = Vector2(3, 3)
			page._input(press)
			_check(page._warn_phase == 0, "hidden cached page does not react to global press")
	else:
		_check(not is_instance_valid(page), "old delayed callback safely expires after destroy")


func _test_current_warning() -> void:
	var page: Variant = await _open()
	page._lives = 2
	page._on_wrong_guess(0, 0)
	await create_timer(1.9).timeout
	_check(game.has_shown_warn_life() and page._warn_phase == 1 and page._warn_click_allowed, "current one-life warning still appears and becomes dismissible")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	page._input(press)
	_check(page._warn_phase == 2, "current warning responds to dismissal")
	page._reset_life_warning()
	page._show_life_warning()
	await create_timer(0.3).timeout
	page._reset_life_warning()
	page._show_life_warning()
	await create_timer(0.25).timeout
	_check(not page._warn_click_allowed, "old unlock delay cannot shorten new warning protection")
	await create_timer(0.3).timeout
	_check(page._warn_click_allowed, "new warning unlocks at its own deadline")
	ui.hide_ui("game")
	_check(page._warn_phase == 0 and not page._warn_click_allowed, "hide resets phase and input permission")


func _test_covered_warning() -> void:
	var page: Variant = await _open()
	page._lives = 2
	page._on_wrong_guess(0, 0)
	var generation: int = page._business_generation
	# 模拟窗口管理器的遮挡合同：visible=false，但不调用 on_hide / 不改变展示代次。
	page.visible = false
	await create_timer(1.4).timeout
	page.visible = true
	_check(page._business_generation == generation and page._is_round_entry_ready(), "occlusion retains same active page generation")
	_check(page._board_view.mouse_filter == Control.MOUSE_FILTER_STOP, "occlusion cannot leave wrong-move board lock behind")
	_check(not page._wrong_guess_pending, "covered wrong-move feedback releases its business lock")
	_check(not game.has_shown_warn_life(), "invisible page does not consume warning eligibility")
	page._maybe_show_life_warning()
	page.visible = false
	await create_timer(0.6).timeout
	page.visible = true
	_check(page._warn_phase == 1 and page._warn_click_allowed, "covered popup unlock deadline still completes")


func _trigger_error(page: Variant, kind: String, lives: int) -> void:
	page._lives = lives
	var wrong := Vector2i(-1, -1)
	for row: int in page._level_config.size:
		for col: int in page._level_config.size:
			if not page._puzzle.solution[row][col]:
				wrong = Vector2i(row, col)
				break
		if wrong.x >= 0:
			break
	if kind == "guess":
		page._on_wrong_guess(wrong.x, wrong.y)
	else:
		while page._draft_busy:
			await process_frame
		page._on_draft_btn_pressed()
		while page._draft_busy:
			await process_frame
		page._board_view.get_board_state().set_cell_state(wrong.x, wrong.y, CellState.DRAFT_CAT)
		page._board_view.refresh_from_model()
		page._on_apply_btn_pressed()
	_check(page._lives == lives - 1 and page._wrong_guess_pending, kind + " actual action starts error feedback and loses one life")


func _test_covered_error_timers(mode: String, kind: String) -> void:
	var page: Variant = await _open(mode)
	var label: String = mode + "/" + kind
	await _trigger_error(page, kind, 3)
	var generation: int = page._business_generation
	page.visible = false
	await create_timer(0.75).timeout
	_check(page._business_generation == generation and page._is_round_entry_ready(), label + " covered feedback still owns the same round")
	_check(not page._wrong_guess_pending and not page._is_complete, label + " covered nonterminal feedback releases its business lock")
	page.visible = true
	# 用同一真实页面继续触发最后一条命，覆盖另一条0.6秒路径。
	page._wrong_guess_pending = false # 独立验证终局计时，即使前一断言失败也能走到真实草稿入口。
	await _trigger_error(page, kind, 1)
	page.visible = false
	await create_timer(0.85).timeout
	var slot: String = "main" if mode == "game" else "daily"
	var settlement: Dictionary = game.get_core_store().snapshot().product_settlements.get(slot, {})
	_check(not page._wrong_guess_pending and page._is_complete, label + " covered terminal feedback finishes its lock and settlement")
	_check(settlement.get("receipt", {}).get("outcome") == "fail", label + " covered last-life error durably settles failure")
	page.visible = true


func _test_revived_error_timers(mode: String, kind: String) -> void:
	var page: Variant = await _open(mode)
	var label: String = mode + "/" + kind
	await _trigger_error(page, kind, 1)
	# 提前完成旧失败并真实复活，再开始下一次尝试；旧计时比新计时早0.25秒。
	await create_timer(0.25).timeout
	page._on_game_fail()
	_check(page._is_complete, label + " old attempt is settled before its delayed callback")
	page._on_revive_requested()
	_check(not page._is_complete and page._business_attempt_sequence == 1, label + " actual revive advances attempt identity")
	page._wrong_guess_pending = false # 旧反馈尚未走完，下一次真实错误负责自己的新锁。
	await _trigger_error(page, kind, 1)
	await create_timer(0.2).timeout
	_check(page._wrong_guess_pending, label + " old feedback cannot clear the newer attempt's lock early")
	await create_timer(0.23).timeout
	_check(not page._is_complete, label + " old terminal delay cannot settle the revived attempt early")
	await create_timer(0.35).timeout
	_check(not page._wrong_guess_pending and page._is_complete, label + " newer attempt finishes at its own feedback/settlement deadline")
	_check(root.get_node("Tracker").get_stat("gamedie_count") == 2, label + " both legitimate failed attempts count exactly once")


func _test_cancelled_error_timers(kind: String, transition: String) -> void:
	var page: Variant = await _open()
	await _trigger_error(page, kind, 1)
	ui.hide_ui("game")
	if transition == "reopen":
		ui.show_ui("game", {"level_index": 50})
	var generation: int = page._business_generation
	page._wrong_guess_pending = true
	await create_timer(0.85).timeout
	_check(page._business_generation == generation and page._wrong_guess_pending, kind + " old feedback cannot modify " + transition + " generation")
	_check(not page._is_complete, kind + " cancelled old terminal cannot complete " + transition + " page")
	var fail: Variant = ui.get_ui("fail")
	_check(fail == null or not fail.is_showing(), kind + " cancelled old terminal cannot open failure UI after " + transition)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
