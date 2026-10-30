## 真实主线/每日：提交通知同步重入时，终局事实一次发布，旧展示不能操作新局。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var tracker: Node


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
	tracker = root.get_node("Tracker")
	var ab: Node = root.get_node("ABTestManager")
	ab.dc_level.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	ab.normal_endgame_save.set_debug_override(0)
	ab.daily_streak.set_debug_override(0)
	for mode: String in ["game", "daily_game"]:
		for outcome: String in ["fail", "win", "quit"]:
			await _test_reentry(mode, outcome, "repeat")
			await _test_reentry(mode, outcome, "hide")
			await _test_reentry(mode, outcome, "reopen")
			await _test_first_round_reentry(mode, outcome)
		await _test_analytics_identity(mode)
	ui.hide_all()
	await create_timer(0.6).timeout
	print("GAME TERMINAL PUBLICATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open(mode: String) -> Variant:
	ui.hide_all()
	await create_timer(0.15).timeout
	_check(game.reset_all(), "isolated state reset")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	await _wait_ready(page)
	_check(page._is_round_entry_ready(), mode + " actual page enters successfully")
	return page


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame


func _terminal(page: Variant, outcome: String) -> void:
	match outcome:
		"fail": page._on_game_over()
		"win": page._on_game_complete()
		"quit": page._on_restart_requested()


func _prepare_terminal(page: Variant, outcome: String) -> void:
	page._stat_start_ms = Time.get_ticks_msec() - 10000
	if outcome == "fail":
		page._lives = 0
	elif outcome == "win":
		for row: int in page._level_config.size:
			for col: int in page._level_config.size:
				page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT if page._puzzle.solution[row][col] else CellState.EMPTY)
		page._board_view.refresh_from_model()


func _test_reentry(mode: String, outcome: String, transition: String) -> void:
	var page: Variant = await _open(mode)
	_prepare_terminal(page, outcome)
	var game_type: String = "normal" if mode == "game" else "daily"
	var slot: String = "main" if mode == "game" else "daily"
	var before_deaths: int = tracker.get_stat("gamedie_count")
	var before_total: int = game.get_game_total_stat(game_type, "time_total")
	var expected_time: int = int(page._build_game_end_params(outcome).time)
	var before_generation: int = page._business_generation
	var state: Dictionary = {"called": false, "generation": -1}
	var listener := func(_revision: int) -> void:
		if state.called:
			return
		var entry: Dictionary = game.get_core_store().snapshot().get("product_settlements", {}).get(slot, {})
		if entry.get("receipt", {}).get("outcome") != outcome:
			return
		state.called = true
		if transition == "repeat":
			# Three nested requests cover fail/win duplicate publication and restart recursion.
			for _attempt: int in 3:
				_terminal(page, outcome)
		else:
			ui.hide_ui(mode)
			if transition == "hide":
				ui.show_ui("home")
			else:
				ui.show_ui(mode, {"level_index": game.get_current_level()} if mode == "game" else {})
				state.generation = page._business_generation
	game.get_core_store().committed.connect(listener)
	_terminal(page, outcome)
	game.get_core_store().committed.disconnect(listener)
	_check(state.called, "%s %s %s reached actual commit boundary" % [mode, outcome, transition])
	await create_timer(0.12).timeout
	var terminal_name: String = ("win" if mode == "game" else "daily_win") if outcome == "win" else ("fail" if mode == "game" else "daily_fail")
	var terminal: Variant = ui.get_ui(terminal_name)
	if transition == "hide":
		_check(not page.is_showing() and not page.visible, "old terminal cannot reopen a hidden game")
		_check(terminal == null or not terminal.is_showing(), "old terminal cannot open a result window after leaving")
	elif transition == "reopen":
		await _wait_ready(page)
		_check(page._business_generation == state.generation, "old terminal cannot restart/replace newly opened game")
		_check(page._is_round_entry_ready() and not page._is_complete, "new page remains ready and playable")
		_check(terminal == null or not terminal.is_showing(), "old result never appears on new page generation")
		_check(page._round_transition.is_empty(), "old guard cannot hold new round hostage")
	else:
		if outcome == "quit":
			await _wait_ready(page)
			_check(page._business_generation == before_generation + 1, "reentrant restart enters exactly once")
			_check(not page._is_complete and page._is_round_entry_ready(), "restart produces a playable board")
		else:
			_check(page._is_complete, "terminal result is presented to current game")
			_check(tracker.get_stat("gamedie_count") - before_deaths == (1 if outcome == "fail" else 0), "nested terminal callbacks count death at most once")
			_check(game.get_game_total_stat(game_type, "time_total") - before_total >= expected_time and game.get_game_total_stat(game_type, "time_total") - before_total <= expected_time + 1, "one committed terminal contributes one elapsed duration")
			var total: int = game.get_game_total_stat(game_type, "time_total")
			_terminal(page, outcome)
			_check(game.get_game_total_stat(game_type, "time_total") == total, "later repeated callback does not count again")
			if outcome == "fail":
				page._on_revive_requested()
				_check(not page._is_complete and page._lives > 0 and page._business_attempt_sequence == 1, "revive remains usable after guarded fail")
				page._lives = 0
				page._on_game_over()
				_check(page._is_complete and tracker.get_stat("gamedie_count") == before_deaths + 2, "next legitimate failed attempt has its own publication")


func _test_first_round_reentry(mode: String, outcome: String) -> void:
	var page: Variant = await _open(mode)
	_prepare_terminal(page, outcome)
	_check(page._business_session == null, "first terminal starts with lazy business session")
	var slot: String = "doku/main" if mode == "game" else "doku/daily"
	var state: Dictionary = {"called": false, "generation": -1}
	var listener := func(_revision: int) -> void:
		if state.called or not game.get_core_store().snapshot().get("round_services", {}).has(slot):
			return
		state.called = true
		ui.hide_ui(mode)
		ui.show_ui(mode, {"level_index": game.get_current_level()} if mode == "game" else {})
		state.generation = page._business_generation
	game.get_core_store().committed.connect(listener)
	_terminal(page, outcome)
	game.get_core_store().committed.disconnect(listener)
	await _wait_ready(page)
	_check(state.called, "reentry reaches initial round creation notification")
	_check(page._business_generation == state.generation and page._is_round_entry_ready() and not page._is_complete, "old initial terminal cannot touch replacement session")
	_check(page._round_transition.is_empty(), "initial commit reentry releases old transition without locking new page")


func _test_analytics_identity(mode: String) -> void:
	var page: Variant = await _open(mode)
	var params: Dictionary = page._build_game_end_params("fail")
	var game_type: String = str(params.game_type)
	_check(params.game_id == game.get_persisted_game_id(game_type), "terminal request captures originating game identity")
	game.set_persisted_game_id(game_type, "new-round-after-callback")
	var before_total: int = game.get_game_total_stat(game_type, "time_total")
	var before_deaths: int = tracker.get_stat("gamedie_count")
	params.time = 17
	page._publish_round_end({"ok": true}, params)
	_check(game.get_game_total_stat(game_type, "time_total") == before_total and tracker.get_stat("gamedie_count") == before_deaths, "old committed fact cannot increment newly assigned round")
	params.game_id = game.get_persisted_game_id(game_type)
	page._publish_round_end({"ok": true, "duplicate": true}, params)
	_check(game.get_game_total_stat(game_type, "time_total") == before_total and tracker.get_stat("gamedie_count") == before_deaths, "duplicate receipt never publishes death or elapsed statistics")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
