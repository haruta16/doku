## 扩展审查：连续棋盘操作的同步通知、轴按钮状态，以及自动演出的资源收尾。
extends SceneTree
var checks: int = 0
var failures: int = 0
var ui: Node
var game: Node
var sound: Node
var action_script: Script

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
	game = root.get_node("GameState")
	sound = root.get_node("SoundManager")
	action_script = load("res://products/meowdoku/gameplay/presentation/input/cell_action.gd")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	ab.daily_streak.set_debug_override(0)
	for kind: String in ["stroke", "correct_cat", "wrong_cat", "clear", "auto_cross", "auto_complete", "lock_cross"]:
		await _test_reentrant_board(kind)
	for flag: String in ["_wrong_guess_pending", "_is_complete", "_settlement_pending", "_auto_completing"]:
		await _test_axis_gate(flag)
	await _test_axis_normal()
	await _test_lock_clear()
	_test_sound_scopes()
	await _test_auto_replacement_and_finish()
	for debug_entry: bool in [false, true]:
		await _test_auto_destroy(debug_entry)
	for kind: String in ["axis_cross", "axis_uncross", "lock_cat", "lock_ordered", "auto_cross"]:
		await _test_cross_destroy(kind)
	ui.hide_all()
	await create_timer(0.6).timeout
	print("GAME OPERATION LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _open() -> Variant:
	ui.hide_all()
	await create_timer(0.15).timeout
	_check(game.reset_all(), "isolated state reset")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	var page: Variant = ui.show_ui("game", {"level_index": 50})
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._entry_ready, "actual page ready")
	return page

func _test_reentrant_board(kind: String) -> void:
	var page: Variant = await _open()
	if kind in ["clear", "lock_cross"]:
		for col: int in page._level_config.size:
			page._board_view.get_board_state().set_cell_state(0, col, CellState.MARK)
		page._board_view.refresh_from_model()
	if kind == "auto_complete":
		page._gameplay_policy.auto_complete_marks = true
	var state: Dictionary = {"called": false, "extra_notifications": 0}
	var callback := func(_r: int, _c: int, _s: int, _source: int) -> void:
		if state.called:
			state.extra_notifications += 1
			return
		state.called = true
		ui.show_ui("game", {"level_index": 50})
		state.board = page._board_view.get_board().duplicate(true)
		state.history = page._current_step_cells.duplicate(true)
		state.lives = page._lives
		state.stats = root.get_node("Tracker").get_stat("step_used")
	page._board_view.cell_state_changed.connect(callback)
	match kind:
		"stroke":
			var actions: Variant = Array([], TYPE_OBJECT, &"RefCounted", action_script)
			actions.append(action_script.set_cell(0, 0, CellState.EMPTY, CellState.MARK))
			actions.append(action_script.set_cell(0, 1, CellState.EMPTY, CellState.MARK))
			page._consume_board_actions(actions)
		"correct_cat", "wrong_cat":
			var correct: bool = kind == "correct_cat"
			for col: int in page._level_config.size:
				if bool(page._puzzle.solution[0][col]) == correct:
					page._consume_double_tap(0, col)
					break
		"clear": page._on_clear_btn_pressed()
		"auto_cross":
			var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
			page._spread_auto_cross(Vector2i(0, 0), 0.0, cells)
		"auto_complete": page._run_auto_complete(page._auto_complete_token)
		"lock_cross":
			var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
			page._spread_status_lock_from_cat(Vector2i(1, 1), cells)
	await create_timer(1.2).timeout
	page._board_view.cell_state_changed.disconnect(callback)
	_check(state.called, kind + " reaches real board notification")
	if state.called:
		_check(state.extra_notifications == 0, kind + " old batch stops notifications after replacement")
		_check(page._current_step_cells == state.history, kind + " old batch cannot append history to replacement round")
		_check(page._lives == state.lives, kind + " old move cannot reduce replacement round lives")
		_check(root.get_node("Tracker").get_stat("step_used") == state.stats, kind + " old move cannot increment replacement round steps")

func _test_axis_gate(flag: String) -> void:
	var page: Variant = await _open()
	page._gameplay_policy.auto_mark_variant = 2
	page._board_view.set_axis_auto_mark_enabled(true)
	var before: Array = page._board_view.get_board().duplicate(true)
	page.set(flag, true)
	page._board_view.get_axis_auto_mark_btn(0, 0).get_node("Hit").pressed.emit()
	await create_timer(0.8).timeout
	_check(page._board_view.get_board() == before, "axis input respects " + flag)
	page.set(flag, false)

func _test_axis_normal() -> void:
	var page: Variant = await _open()
	page._gameplay_policy.auto_mark_variant = 2
	page._board_view.set_axis_auto_mark_enabled(true)
	var button: Variant = page._board_view.get_axis_auto_mark_btn(0, 0)
	button.get_node("Hit").pressed.emit()
	await create_timer(0.8).timeout
	_check(page._board_view.get_board()[0].all(func(value: int) -> bool: return value == CellState.MARK), "normal axis marks complete row")
	button.get_node("Hit").pressed.emit()
	await create_timer(0.8).timeout
	_check(page._board_view.get_board()[0].all(func(value: int) -> bool: return value == CellState.EMPTY), "normal axis clears complete row")
	_check(page._axis_busy_set.is_empty() and not page._board_view.is_cell_input_locked(0, 0), "normal axis releases input")

func _test_lock_clear() -> void:
	var page: Variant = await _open()
	page._gameplay_policy.auto_mark_variant = int(root.get_node("ABTestManager").game_auto_mark.VALUE_LOCK_X)
	var cat_col: int = 0
	for col: int in page._level_config.size:
		if page._puzzle.solution[0][col]: cat_col = col
		page._board_view.get_board_state().set_cell_state(0, col, CellState.CAT if page._puzzle.solution[0][col] else CellState.MARK)
	page._board_view.refresh_from_model()
	var mark_col: int = (cat_col + 1) % page._level_config.size
	page._on_cell_changed_for_lock_x(0, mark_col, CellState.MARK, 0)
	_check(page._board_view.is_cell_input_locked(0, mark_col), "actual LOCK_X callback locks pending mark")
	page._on_clear_btn_pressed()
	await create_timer(1.2).timeout
	_check(page._board_view.get_cell_state(0, mark_col) == CellState.EMPTY, "clear removes pending mark using existing product behavior")
	_check(not page._board_view.is_cell_input_locked(0, mark_col), "cleared pending lock animation cannot leave empty cell unplayable")

func _test_auto_destroy(debug_entry: bool) -> void:
	var page: Variant = await _open()
	page._gameplay_policy.auto_complete_enabled = true
	page._gameplay_policy.auto_complete_marks = true
	var size: int = page._level_config.size
	for row: int in size - 1:
		for col: int in size:
			if page._puzzle.solution[row][col]:
				page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT)
	page._board_view.refresh_from_model()
	page._refresh_auto_complete_btn()
	page._ac_btn.modulate.a = 1.0
	var before: int = UIMask._ref_count
	if debug_entry:
		var args: Array[String] = []
		page._cmd_win(args)
	else: page._on_auto_complete_btn_pressed()
	_check(page._auto_completing and UIMask._ref_count == before + 1, "actual auto completion owns an input mask")
	var overlay: WeakRef = weakref(page._strategy_overlay)
	var timer: WeakRef = weakref(page._auto_complete_timer)
	page._do_destroy()
	page.queue_free()
	await create_timer(1.5).timeout
	_check(not is_instance_valid(page), "page destruction really completed")
	_check(overlay.get_ref() == null, "destroy frees the strategy overlay owned outside the page tree")
	_check(timer.get_ref() == null, "destroy frees the actual completion timer and its waiting signal")
	_check(UIMask._ref_count == before, "destroy releases auto completion mask even without coroutine returning")
	_check(not sound.is_silent(), "destroy releases auto completion sound suppression")
	# 清理旧实现留下的全局状态，避免反证污染下一个独立场景。
	while UIMask._ref_count > before: UIMask.release()
	sound.set_silent(false)

## 五种逐格演出都在真实计时等待中销毁，确保等待源归页面所有。
func _test_cross_destroy(kind: String) -> void:
	var page: Variant = await _open()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	for cell: Vector2i in cells:
		var state: int = CellState.MARK if kind in ["lock_cat", "lock_ordered", "axis_uncross"] else CellState.EMPTY
		page._board_view.get_board_state().set_cell_state(cell.x, cell.y, state)
	page._board_view.refresh_from_model()
	match kind:
		"axis_cross": page._spread_axis_cross(0, 0, cells)
		"axis_uncross": page._spread_axis_uncross(0, 0)
		"lock_cat": page._spread_status_lock_from_cat(Vector2i(1, 1), cells)
		"lock_ordered": page._spread_status_lock_ordered(cells)
		"auto_cross": page._spread_auto_cross(Vector2i(1, 1), 0.2, cells)
	_check(page._board_view.is_cell_input_locked(0, 1), kind + " begins pending animation")
	var pending: Array[WeakRef] = []
	for timer: Timer in page._managed_timers:
		pending.append(weakref(timer))
	_check(not pending.is_empty(), kind + " owns its pending animation timer")
	page._do_destroy()
	page.queue_free()
	await create_timer(0.7).timeout
	_check(not is_instance_valid(page), kind + " page is fully destroyed")
	for timer: WeakRef in pending:
		_check(timer.get_ref() == null, kind + " destruction frees the pending timer and its waiting signal")


func _test_sound_scopes() -> void:
	sound.set_silent(false)
	var first: RefCounted = sound.hold_silence()
	var second: RefCounted = sound.hold_silence()
	_check(sound.is_silent(), "two active effects suppress sound")
	first = null
	_check(sound.is_silent(), "old effect ending cannot unmute another effect")
	second = null
	_check(not sound.is_silent(), "last effect release restores sound")
	sound.set_silent(true)
	var scope: RefCounted = sound.hold_silence()
	scope = null
	_check(sound.is_silent(), "temporary completion cannot unmute legacy tutorial")
	sound.set_silent(false)
	_check(not sound.is_silent(), "tutorial mute retains its existing switch behavior")

func _prepare_auto(page: Variant) -> void:
	page._gameplay_policy.auto_complete_enabled = true
	page._gameplay_policy.auto_complete_marks = true
	for row: int in page._level_config.size - 1:
		for col: int in page._level_config.size:
			if page._puzzle.solution[row][col]:
				page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT)
	page._board_view.refresh_from_model()
	page._refresh_auto_complete_btn()
	page._ac_btn.modulate.a = 1.0

func _test_auto_replacement_and_finish() -> void:
	var page: Variant = await _open()
	_prepare_auto(page)
	var masks: int = UIMask._ref_count
	page._on_auto_complete_btn_pressed()
	_check(UIMask._ref_count == masks + 1 and sound.is_silent(), "first actual auto completion holds resources")
	ui.show_ui("game", {"level_index": 50})
	_check(UIMask._ref_count == masks and not sound.is_silent(), "same-page refresh immediately cancels old resources")
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not page._auto_completing and not page._is_complete, "replacement entry remains playable after old coroutine expires")
	_prepare_auto(page)
	page._on_auto_complete_btn_pressed()
	await create_timer(2.5).timeout
	_check(page._is_complete and game.get_current_level() == 51, "new normal auto completion still wins exactly once")
	_check(UIMask._ref_count == masks and not sound.is_silent(), "normal completion releases mask and sound")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
