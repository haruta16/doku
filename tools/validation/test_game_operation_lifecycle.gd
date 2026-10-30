## 1.22 操作边界：真实页面的同步重入、鼠标/草稿门禁、终局奖励和演出资源销毁。
extends SceneTree
var checks: int = 0
var failures: int = 0
var ui: Node
var game: Node
var sound: Node
var files: Variant
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
	files = game.get_core_store().get("_file_store")
	action_script = load("res://products/meowdoku/gameplay/presentation/input/cell_action.gd")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.win_encourage.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	ab.daily_streak.set_debug_override(0)
	ab.prop_mouse.set_debug_override(1)
	ab.draft_mode.set_debug_override(5)
	for kind: String in ["stroke", "correct_cat", "wrong_cat", "draft", "mouse", "debug_complete"]:
		await _test_reentrant_board(kind)
	for flag: String in ["_wrong_guess_pending", "_is_complete", "_settlement_pending", "_mouse_tool_busy", "_entry_anim_playing"]:
		await _test_tool_gate(flag)
	await _test_draft_and_mouse_finish()
	_test_sound_scopes()
	await _test_auto_replacement_and_finish()
	for kind: String in ["debug_complete", "mouse", "mouse_cat", "auto_x_bonus"]:
		await _test_effect_destroy(kind)
	await _test_auto_x_transaction()
	ui.hide_all()
	for name: String in ["game", "confirm", "win", "fail"]:
		await ui.destroy_ui(name)
	await process_frame
	await process_frame
	print("GAME OPERATION LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _open() -> Variant:
	ui.hide_all()
	await create_timer(0.8).timeout
	_check(game.reset_all(), "isolated state reset")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("mouse", 5)
	game.set_tool_count("draft", 5)
	var page: Variant = ui.show_ui("game", {"level_index": 50})
	await _wait_ready(page)
	return page

func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing or page._tool_btns_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._entry_ready and not page._entry_anim_playing and not page._tool_btns_locked, "actual page ready")

func _test_reentrant_board(kind: String) -> void:
	var page: Variant = await _open()
	page._active_slot = page._ensure_slot(-2)
	if kind == "draft":
		page._on_draft_btn_pressed()
		page._active_slot = page._ensure_slot(-2)
		page._set_cell_draft(0, 0, CellState.DRAFT_CROSS)
		page._set_cell_draft(0, 1, CellState.DRAFT_CROSS)
	var state: Dictionary = {"called": false, "extra": 0}
	var callback := func(_r: int, _c: int, _s: int, _source: int) -> void:
		if state.called:
			state.extra += 1
			return
		state.called = true
		ui.show_ui("game", {"level_index": 50})
	page._board_view.cell_state_changed.connect(callback)
	match kind:
		"draft": page._apply_draft_commit()
		"stroke":
			var actions: Variant = Array([], TYPE_OBJECT, &"RefCounted", action_script)
			for col: int in 3:
				actions.append(action_script.set_draft(0, col, CellState.DRAFT_CROSS) if kind == "draft" else action_script.set_cell(0, col, CellState.EMPTY, CellState.MARK))
			page._consume_board_actions(actions)
		"correct_cat", "wrong_cat":
			for col: int in page._level_config.size:
				if bool(page._puzzle.solution[0][col]) == (kind == "correct_cat"):
					page._consume_double_tap(0, col, false)
					break
		"mouse": page._try_start_mouse_tool()
		"debug_complete": _debug_win(page)
	await _wait_ready(page)
	await create_timer(1.2).timeout
	page._board_view.cell_state_changed.disconnect(callback)
	_check(state.called, kind + " reaches real board notification")
	_check(state.extra == 0, kind + " stops old synchronous and deferred notifications after replacement")
	_check(page._lives == page._life_cap and not page._wrong_guess_pending, kind + " cannot damage replacement life/interaction state")
	_check(not page._mouse_tool_busy and not page._auto_completing, kind + " cannot retain an old effect owner")
	var stable: Dictionary = page._business_runtime()
	await create_timer(0.3).timeout
	_check(page._business_runtime() == stable, kind + " old callbacks cannot change replacement board, score or history")

func _test_tool_gate(flag: String) -> void:
	var page: Variant = await _open()
	var before: Dictionary = game.get_core_candidate()
	var board: Array = page._board_view.get_board()
	page.set(flag, true)
	page._try_start_mouse_tool()
	if flag != "_mouse_tool_busy":
		page._on_draft_btn_pressed()
	_check(game.get_core_candidate() == before and page._board_view.get_board() == board, "paid 1.22 tool input respects " + flag)
	page.set(flag, false)

func _test_draft_and_mouse_finish() -> void:
	var page: Variant = await _open()
	page._on_draft_btn_pressed()
	_check(page._draft_mode and game.get_tool_count("draft") == 4, "actual draft button commits activation once")
	page._active_slot = page._ensure_slot(-2)
	var actions: Variant = Array([], TYPE_OBJECT, &"RefCounted", action_script)
	actions.append(action_script.set_draft(0, 0, CellState.DRAFT_CROSS))
	page._consume_board_actions(actions)
	page._exit_draft_mode_and_clear()
	_check(not page._draft_mode and page._board_view.get_cell_state(0, 0) == CellState.EMPTY, "draft clear completes through transaction")
	page._try_start_mouse_tool()
	_check(page._mouse_tool_busy and game.get_tool_count("mouse") == 4, "actual mouse action spends exactly once before presentation")
	var committed: Array = page._board_view.get_board()
	var deadline: int = Time.get_ticks_msec() + 6000
	while page._mouse_tool_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not page._mouse_tool_busy and page._board_view.is_touch_enabled(), "mouse completion releases input")
	_check(page._board_view.get_board() == committed, "mouse animation consumes its committed board without rewriting it")

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
	_check(sound.is_silent(), "temporary effect cannot unmute tutorial")
	sound.set_silent(false)

func _test_auto_replacement_and_finish() -> void:
	var page: Variant = await _open()
	var masks: int = UIMask._ref_count
	_debug_win(page)
	_check(UIMask._ref_count == masks + 1 and sound.is_silent(), "debug win owns mask and a sound lease")
	ui.show_ui("game", {"level_index": 50})
	_check(UIMask._ref_count == masks and not sound.is_silent(), "same-page refresh immediately releases old resources")
	await _wait_ready(page)
	await create_timer(0.2).timeout
	_check(not page._auto_completing and not page._is_complete, "replacement remains playable after old coroutine expires")
	_debug_win(page)
	await create_timer(3.0).timeout
	_check(page._is_complete and game.get_current_level() == 51, "current debug completion still wins exactly once")
	_check(UIMask._ref_count == masks and not sound.is_silent(), "normal debug completion releases mask and sound")

func _test_effect_destroy(kind: String) -> void:
	var page: Variant = await _open()
	var before: int = UIMask._ref_count
	if kind == "mouse_cat":
		_complete_board(page)
		for row: int in page._level_config.size:
			for col: int in page._level_config.size:
				if not page._puzzle.solution[row][col]:
					page._board_view.get_board_state().set_cell_state(row, col, CellState.MARK)
		for col: int in page._level_config.size:
			if page._puzzle.solution[0][col]:
				page._board_view.get_board_state().set_cell_state(0, col, CellState.EMPTY)
				break
		page._board_view.refresh_from_model()
	match kind:
		"debug_complete": _debug_win(page)
		"mouse", "mouse_cat": page._try_start_mouse_tool()
		"auto_x_bonus":
			page._gameplay_policy.auto_x_fill_variant = 2
			_complete_board(page)
			var won: Dictionary = page._settle_current_main_or_preview(page._business_settlement_id(), "win")
			_check(won.get("ok", false), "auto-x destroy fixture commits its terminal bonus first")
			page._accept_win_bonus(won)
			page._play_auto_cross_bonus_sequence()
	var overlay: WeakRef = weakref(page._strategy_overlay)
	var durable: Dictionary = game.get_core_candidate()
	page._do_destroy()
	page.queue_free()
	await create_timer(1.5).timeout
	_check(not is_instance_valid(page), kind + " destruction completed during pending animation")
	_check(overlay.get_ref() == null, kind + " frees overlay outside page tree")
	_check(UIMask._ref_count == before and not sound.is_silent(), kind + " releases mask/sound even if awaiting coroutine never returns")
	_check(game.get_core_candidate() == durable, kind + " old animation cannot mutate durable facts after destroy")

func _complete_board(page: Variant) -> void:
	var board: Array = page._board_view.get_board()
	for row: int in board.size():
		for col: int in board[row].size():
			board[row][col] = CellState.CAT if page._puzzle.solution[row][col] else CellState.EMPTY
	page._board_view.get_board_state().apply_committed_board(board, Time.get_ticks_msec())
	page._board_view.refresh_from_model()

func _test_auto_x_transaction() -> void:
	var page: Variant = await _open()
	page._gameplay_policy.auto_x_fill_variant = 2
	page._gameplay_policy.win_encourage_variant = 0
	_complete_board(page)
	var runtime: Dictionary = page._win_business_runtime()
	var expected: int = runtime.performance.score
	_check(expected > page._score_model.score, "terminal projection includes auto-cross score before any animation")
	var attempt: String = page._business_settlement_id()
	var before: Dictionary = game.get_core_candidate()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed: Dictionary = page._settle_current_main_or_preview(attempt, "win")
	files.set_fault_injector_for_tests(Callable())
	if failed.get("ok", false) or game.get_core_candidate() != before:
		print("TERMINAL_FAILURE_DIFFERENCE ", _changed_paths(before, game.get_core_candidate()), " result=", failed.get("error", "ok"))
	_check(not failed.get("ok", false) and game.get_core_candidate() == before, "failed terminal save cannot commit cross bonus, marks or advancement")
	var won: Dictionary = page._settle_current_main_or_preview(attempt, "win")
	_check(won.get("ok", false), "terminal bonus save retries successfully")
	page._accept_win_bonus(won)
	_check(page._score_model.score == expected, "successful terminal accepts authoritative bonus exactly once")
	var committed: Dictionary = game.get_core_candidate()
	var duplicate: Dictionary = page._settle_current_main_or_preview(attempt, "win")
	page._accept_win_bonus(duplicate)
	_check(duplicate.get("duplicate", false) and game.get_core_candidate() == committed and page._score_model.score == expected, "terminal retry cannot add auto-cross reward twice")
	page._is_complete = true
	page._play_auto_cross_bonus_sequence()
	ui.hide_ui("game")
	await create_timer(1.2).timeout
	_check(game.get_core_candidate() == committed, "hiding before auto-cross animation leaves its complete durable reward unchanged")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)

func _debug_win(page: Variant) -> void:
	var args: Array[String] = []
	page._cmd_win(args)

func _changed_paths(before: Variant, after: Variant, path: String = "") -> Array:
	var result: Array = []
	if typeof(before) != typeof(after):
		return [path + " [type %s -> %s]" % [type_string(typeof(before)), type_string(typeof(after))]]
	if before is Dictionary:
		for key: Variant in before:
			if not after.has(key):
				result.append(path + "/" + str(key) + " [removed]")
		for key: Variant in after:
			if not before.has(key):
				result.append(path + "/" + str(key) + " [added]")
			else:
				result.append_array(_changed_paths(before[key], after[key], path + "/" + str(key)))
	elif before is Array:
		if before.size() != after.size():
			result.append(path + " [size]")
		for index: int in mini(before.size(), after.size()):
			result.append_array(_changed_paths(before[index], after[index], path + "/" + str(index)))
	elif before != after:
		result.append(path + " [%s -> %s]" % [str(before), str(after)])
	return result
