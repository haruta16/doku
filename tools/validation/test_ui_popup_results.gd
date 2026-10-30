## 真实评分、反馈与确认弹窗：重复动作及关闭动画不能跨展示发结果。
extends SceneTree

var checks: int = 0
var failures: int = 0
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
	ui = root.get_node("UIManager")
	root.get_node("GameState").set_sound_on(false)
	await _test_rating()
	await _test_feedback()
	await _test_confirm()
	await _test_setting_close()
	await _test_confirm_back()
	await _test_result_waits()
	await _test_switch_gift()
	await _test_win_reopen()
	await _test_tutorial_iq_reopen()
	await _test_tutorial_feedback_completion()
	ui.hide_all()
	host.queue_free()
	await process_frame
	await process_frame
	print("UI POPUP RESULTS TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_rating() -> void:
	for name: String in ["rate_us", "rate_us_v2"]:
		var page: Variant = ui.show_ui(name)
		await create_timer(0.5).timeout
		var results: Array = []
		var observer := func(data: Dictionary) -> void: results.append(data)
		page.closed.connect(observer)
		page._select_stars(3)
		page._on_rate_us_btn_pressed()
		page._on_rate_us_btn_pressed()
		page._on_close_btn_pressed()
		_check(results.is_empty(), name + " repeated buttons cannot finish before the first animation")
		await create_timer(0.6).timeout
		_check(results.size() == 1 and results[0] == {"star_count": 3, "is_submitted": true}, name + " submits exactly one captured result")
		_check(page.is_hidden(), name + " closes through its manager after completion")
		ui.show_ui(name)
		page._on_close_btn_pressed()
		ui.hide_ui(name)
		ui.show_ui(name)
		await create_timer(0.6).timeout
		_check(results.size() == 1 and page.is_showing() and page.visible, name + " old close cannot finish into a reopened presentation")
		page.closed.disconnect(observer)
		ui.hide_ui(name)

func _test_feedback() -> void:
	var page: Variant = ui.show_ui("feedback")
	var results: Array = []
	var observer := func() -> void: results.append(page.is_submitted)
	page.closed.connect(observer)
	page._text_edit.text = "test"
	page._on_submit_pressed()
	page._on_submit_pressed()
	page._on_close_pressed()
	_check(results.is_empty(), "feedback repeated buttons wait for the first close")
	await create_timer(0.6).timeout
	_check(results == [true] and page.is_hidden(), "feedback submits and closes exactly once")
	ui.show_ui("feedback")
	page._on_close_pressed()
	ui.hide_ui("feedback")
	ui.show_ui("feedback")
	await create_timer(0.6).timeout
	_check(results == [true] and page.is_showing(), "feedback cancelled animation emits no new presentation result")
	page.closed.disconnect(observer)
	ui.hide_ui("feedback")

func _test_confirm() -> void:
	var result := {"confirmed": 0, "closed": 0}
	var params: Dictionary = {"on_confirm": func() -> void: result.confirmed += 1, "on_close": func() -> void: result.closed += 1}
	var page: Variant = ui.show_ui("confirm", params)
	page._on_action_btn_pressed()
	page._on_action_btn_pressed()
	page._on_close_btn_pressed()
	_check(result.confirmed == 1 and result.closed == 0, "confirm preserves immediate callback timing but accepts only the first button")
	await create_timer(0.6).timeout
	_check(page.is_hidden(), "confirm closes through manager lifecycle")
	ui.show_ui("confirm", params)
	page.close()
	ui.show_ui("confirm", params)
	await create_timer(0.6).timeout
	_check(page.is_showing() and page.visible, "confirm old animation cannot hide a refreshed request")
	ui.hide_ui("confirm")


func _test_setting_close() -> void:
	var calls := {"old": 0, "new": 0}
	var old_callback := func() -> void: calls.old += 1
	var new_callback := func() -> void: calls.new += 1
	var page: Variant = ui.show_ui("setting", {"on_close": old_callback})
	await create_timer(0.5).timeout
	ui.hide_ui("setting")
	ui.show_ui("setting", {"on_close": new_callback})
	await create_timer(0.6).timeout
	_check(page.is_showing() and page.visible, "setting old close animation cannot hide the reopened presentation")
	_check(calls == {"old": 0, "new": 0}, "cancelled setting close calls neither the original nor replacement callback")
	await ui.hide_ui("setting")
	_check(calls == {"old": 0, "new": 1}, "setting completed close invokes only its captured callback")
	for skip_animation: bool in [false, true]:
		ui.show_ui("setting", {"on_close": old_callback})
		var reopen := func() -> void:
			if not page.visible:
				ui.show_ui("setting", {"on_close": new_callback})
		page.visibility_changed.connect(reopen)
		page._skip_next_close_anim = skip_animation
		await ui.hide_ui("setting")
		await create_timer(0.5).timeout
		_check(page.is_showing() and page.visible and calls == {"old": 0, "new": 1}, "setting visible callback cancels stale completion (skip animation: %s)" % skip_animation)
		page.visibility_changed.disconnect(reopen)
		await ui.hide_ui("setting")
		calls.new = 1
	ui.show_ui("setting", {"on_close": old_callback})
	page._on_how_to_play_btn_pressed()
	var tutorial: Variant = ui.get_ui("how_to_play_paged")
	_check(page.is_hidden() and tutorial.is_showing(), "setting transfers its close callback to the help presentation")
	tutorial._close()
	_check(calls.old == 1 and calls.new == 1, "normal help close invokes the original setting callback once")
	await create_timer(0.5).timeout
	ui.show_ui("setting", {"on_close": old_callback})
	page._on_how_to_play_btn_pressed()
	ui.show_ui("setting", {"on_close": new_callback})
	tutorial._close()
	_check(calls.old == 1 and calls.new == 1 and page.is_showing(), "old help close cannot borrow a reopened setting callback")
	await ui.hide_ui("setting")
	_check(calls.new == 2, "reopened setting retains its own later close callback")
	await create_timer(0.5).timeout
	ui.show_ui("setting", {"on_close": old_callback})
	page._on_how_to_play_btn_pressed()
	await ui.hide_ui("how_to_play_paged")
	ui.show_ui("how_to_play_paged")
	tutorial._close()
	_check(calls.old == 1 and calls.new == 2, "cancelled help presentation cannot borrow the next help close signal")
	await create_timer(0.5).timeout


func _test_confirm_back() -> void:
	for source: String in ["escape", "android_back"]:
		var underlying: Variant = ui.show_ui("feedback")
		var result := {"confirmed": 0, "closed": 0, "underlying_closed": 0}
		var observer := func() -> void: result.underlying_closed += 1
		underlying.closed.connect(observer)
		var page: Variant = ui.show_ui("confirm", {
			"on_confirm": func() -> void: result.confirmed += 1,
			"on_close": func() -> void: result.closed += 1,
		})
		_dispatch_back(source)
		_dispatch_back(source)
		_check(result.closed == 1 and result.confirmed == 0, source + " cancels the confirmation exactly once while closing")
		await create_timer(0.6).timeout
		_check(page.is_hidden(), source + " closes the confirmation through its manager")
		_check(underlying.is_showing() and result.underlying_closed == 0, source + " never reaches the underlying page")
		underlying.closed.disconnect(observer)
		ui.hide_all()

	var reopened := {"closed": 0}
	var page: Variant = ui.show_ui("confirm", {"content": "first", "on_close": func() -> void:
		reopened.closed += 1
		ui.show_ui("confirm", {"content": "replacement"})
	})
	var revision: int = page.get_presentation_revision()
	_dispatch_back("escape")
	await create_timer(0.6).timeout
	_check(reopened.closed == 1 and page.is_showing() and page.get_presentation_revision() != revision,
		"escape cancellation may replace the popup without the old close hiding it")
	_dispatch_back("android_back")
	await create_timer(0.6).timeout
	_check(page.is_hidden() and reopened.closed == 1, "replacement popup does not reuse the previous cancellation callback")
	ui.hide_all()


func _dispatch_back(source: String) -> void:
	if source == "android_back":
		ui.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		return
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)


func _capture_rating(page: Variant, result: Dictionary, owner: Callable = Callable()) -> void:
	result["data"] = await page.get_script().wait_for_result(page, owner)
	result["done"] = true


func _capture_feedback(page: Variant, result: Dictionary, owner: Callable = Callable()) -> void:
	result["accepted"] = await page.get_script().wait_for_result(page, owner)
	result["done"] = true


func _test_result_waits() -> void:
	var rating: Variant = ui.show_ui("rate_us")
	var result: Dictionary = {"done": false}
	_capture_rating(rating, result)
	rating._select_stars(4)
	rating._on_rate_us_btn_pressed()
	await create_timer(0.6).timeout
	_check(result.get("done", false) and result.get("data", {}) == {"star_count": 4, "is_submitted": true}, "rating waiter receives the completed presentation result")
	_check(rating.closed.get_connections().is_empty(), "rating waiter disconnects after success")
	ui.show_ui("rate_us")
	result = {"done": false}
	_capture_rating(rating, result)
	ui.show_ui("rate_us")
	await process_frame
	await process_frame
	_check(result.get("done", false) and result.get("data", null) == {}, "rating refresh cancels the prior waiter")
	_check(rating.closed.get_connections().is_empty(), "rating refresh removes prior listener")
	result = {"done": false}
	_capture_rating(rating, result)
	rating.free()
	await process_frame
	await process_frame
	_check(result.get("done", false) and result.get("data", null) == {}, "destroying rating page releases its caller")

	var feedback: Variant = ui.show_ui("feedback")
	result = {"done": false}
	_capture_feedback(feedback, result)
	ui.hide_ui("feedback")
	await process_frame
	await process_frame
	_check(result.get("done", false) and not result.get("accepted", true), "external feedback hide cancels its caller")
	_check(feedback.closed.get_connections().is_empty(), "feedback cancellation removes prior listener")
	ui.show_ui("feedback")
	result = {"done": false}
	_capture_feedback(feedback, result)
	feedback._on_close_pressed()
	await create_timer(0.6).timeout
	_check(result.get("done", false) and result.get("accepted", false), "feedback explicit close completes its caller")
	feedback = ui.show_ui("feedback")
	result = {"done": false}
	_capture_feedback(feedback, result)
	feedback.free()
	await process_frame
	await process_frame
	_check(result.get("done", false) and not result.get("accepted", true), "destroying feedback releases its caller")

	rating = ui.show_ui("rate_us")
	var owner: Dictionary = {"active": true}
	result = {"done": false}
	_capture_rating(rating, result, func() -> bool: return owner.active)
	owner.active = false
	await process_frame
	await process_frame
	_check(result.get("done", false) and result.get("data", null) == {} and rating.is_hidden(), "owner cancellation closes only its current rating presentation")
	_check(rating.closed.get_connections().is_empty(), "owner cancellation clears result listener")

	var count := {"value": 0}
	var confirm: Variant = ui.show_ui("confirm", {"content": "first", "on_confirm": func() -> void:
		count.value += 1
		ui.show_ui("confirm", {"content": "retry"})
	})
	var revision: int = confirm.get_presentation_revision()
	confirm._on_action_btn_pressed()
	await create_timer(0.6).timeout
	_check(count.value == 1 and confirm.is_showing() and confirm.visible and confirm.get_presentation_revision() != revision, "confirm callback may synchronously replace its failed request without old close hiding retry")
	ui.hide_ui("confirm")


func _test_switch_gift() -> void:
	var state: Node = root.get_node("GameState")
	var before: int = state.get_tool_count("hint")
	var data: Dictionary = state.get_streak_data()
	data["last_group"] = int(data.get("last_group", 0)) + 1
	var staged: Dictionary = state.commit_streak_transition(data, [{"kind": "hint", "count": 2}], "switch-test")
	_check(staged.get("ok", false), "switch gift registered before showing the page")
	var page: Variant = ui.show_ui("streak_switch1")
	var files: RefCounted = state.get_core_store().get("_file_store")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page._on_action_pressed()
	_check(page.is_showing() and not page._granted and state.get_tool_count("hint") == before, "failed switch gift claim retains page and retry entitlement")
	files.set_fault_injector_for_tests(Callable())
	page._on_action_pressed()
	_check(page.is_hidden() and page._granted and state.get_tool_count("hint") == before + 2, "same switch button retries once and closes only after successful claim")
	page._on_action_pressed()
	_check(state.get_tool_count("hint") == before + 2, "repeated switch action does not grant twice")


func _test_win_reopen() -> void:
	# 延迟消失动画中重开通关页；旧 on_hide 不能复位或隐藏后来的一次展示。
	var board_script: Script = load("res://products/meowdoku/gameplay/presentation/board/board_view.gd")
	var board: Node = board_script.new()
	current_scene.add_child(board)
	var params: Dictionary = {"board_view": board, "level_config": {"level": 1, "skip_appear_delay": true}}
	var page: Variant = ui.show_ui("win", params)
	ui.hide_ui("win")
	ui.show_ui("win", params)
	await create_timer(3.0).timeout
	_check(page.is_showing() and page.visible, "old win hide completion cannot hide a reopened window")
	ui.hide_ui("win")
	await create_timer(0.8).timeout
	board.queue_free()


func _test_tutorial_iq_reopen() -> void:
	root.get_node("ABTestManager").guide_feedback.set_debug_override(2)
	var page: Variant = ui.show_ui("tutorial")
	page._play_iq_feedback()
	await process_frame
	ui.show_ui("tutorial")
	await create_timer(0.5).timeout
	_check(page._iq_label.text == tr("TUTORIAL_IQ_FORMAT") % 60 and page._iq_value == 60, "old IQ tween cannot overwrite a reopened tutorial's initial display")
	page._anim_effect_fireworks.play("Flreworks")
	page._hide_iq_bar_after_fireworks()
	ui.show_ui("tutorial")
	page._anim_effect_fireworks.animation_finished.emit(&"Flreworks")
	await create_timer(0.6).timeout
	_check(page._iq_bar.visible, "old fireworks completion cannot dismiss the reopened IQ tutorial")
	ui.hide_ui("tutorial")
	root.get_node("ABTestManager").guide_feedback.set_debug_override(0)


func _test_tutorial_feedback_completion() -> void:
	var game: Node = root.get_node("GameState")
	for variant: int in [1, 2]:
		root.get_node("ABTestManager").guide_feedback.set_debug_override(variant)
		game.set_tutorial_done(false)
		var page: Variant = ui.show_ui("tutorial")
		await _wait_tutorial_mode(page, page.StepMode.PLACE_CAT)
		_tap_tutorial(page, Vector2i(0, 2))
		_tap_tutorial(page, Vector2i(0, 2))
		await _wait_tutorial_mode(page, page.StepMode.MARK_CELLS)
		for cell: Vector2i in page._allowed_cells.duplicate():
			_tap_tutorial(page, cell)
		await _wait_tutorial_mode(page, page.StepMode.PLACE_CAT)
		_tap_tutorial(page, Vector2i(3, 1))
		_tap_tutorial(page, Vector2i(3, 1))
		await _wait_tutorial_mode(page, page.StepMode.MARK_CELLS)
		for cell: Vector2i in page._allowed_cells.duplicate():
			_tap_tutorial(page, cell)
		await _wait_tutorial_mode(page, page.StepMode.PLACE_CAT)
		_tap_tutorial(page, Vector2i(1, 0))
		_tap_tutorial(page, Vector2i(1, 0))
		await _wait_tutorial_mode(page, page.StepMode.FREE_PLAY)
		_tap_tutorial(page, Vector2i(2, 3))
		_tap_tutorial(page, Vector2i(2, 3))
		await _wait_tutorial_mode(page, page.StepMode.CONFIRM)
		_check(page._board_view.count_cat_cells() == 4, "feedback variant %d reaches completed board" % variant)
		page._confirm_btn.tag_pressed.emit()
		await create_timer(0.6).timeout
		var game_page: Variant = ui.get_ui("game")
		_check(game.is_tutorial_done() and game_page != null and game_page.visible and game_page._entry_error.is_empty(), "feedback variant %d completes into actual first game" % variant)
		ui.hide_ui("game")
		ui.hide_ui("tutorial")
	root.get_node("ABTestManager").guide_feedback.set_debug_override(0)


func _wait_tutorial_mode(page: Variant, mode: int) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while page._current_mode != mode and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._current_mode == mode, "feedback flow reaches interaction mode %d" % mode)


func _tap_tutorial(page: Variant, cell: Vector2i) -> void:
	var view: Control = page._board_view.get_cell_view(cell.x, cell.y)
	page._board_view.cell_drag_start.emit(view.position + view.size * 0.5)
	page._board_view.cell_drag_end.emit()
