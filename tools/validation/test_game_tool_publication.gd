## 真实页面的同步提交通知：一次业务操作只发布一次，旧回执不能覆盖新页面或新提示。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var tracker: Node
var files: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	tracker = root.get_node("Tracker")
	files = game.get_core_store().get("_file_store")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.daily_first_level_difficulty.set_debug_override(0)
	ab.reward_unlock_level.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	ab.auto_x_fill_mode.set_debug_override(0)
	for mode: String in ["game", "daily_game"]:
		await _test_hint_reentry(mode)
		await _test_locate_reentry(mode)
		await _test_failure_retry(mode)
		await _test_failed_then_reentrant_success(mode, "hint")
		await _test_failed_then_reentrant_success(mode, "locate")
		await _test_hidden_result(mode, "hint")
		await _test_hidden_result(mode, "locate")
	await _test_reopened_page("hint")
	await _test_reopened_page("locate")
	await _test_board_signal_reentry(false)
	await _test_board_signal_reentry(true)
	await _test_cross_mode_publication("hint")
	await _test_cross_mode_publication("locate")
	await _test_multi_cell_hint_publication()
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await create_timer(0.7).timeout
	print("GAME TOOL PUBLICATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open(mode: String) -> Variant:
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await create_timer(0.3).timeout
	_check(game.reset_all(), mode + " resets isolated player")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("hint", 5)
	game.set_tool_count("locate", 5)
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	await _wait_ready(page)
	_check(page._is_round_entry_ready() and not page._entry_anim_playing, mode + " real page is ready")
	_check(page._tool_cost("hint") == 1 and page._tool_cost("locate") == 1, mode + " fixture keeps original paid rules")
	_check(page._ensure_business_round().get("ok", false), mode + " starts round before installing action listener")
	return page


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing or page._tool_btns_locked) and Time.get_ticks_msec() < deadline:
		await process_frame


func _saved(mode: String) -> Dictionary:
	return game.get_core_store().snapshot().round_services["doku/" + ("main" if mode == "game" else "daily")]


func _press(page: Variant, kind: String) -> void:
	if kind == "hint":
		page._bt._hint_btn.pressed.emit()
	else:
		page._bt._locate_btn.pressed.emit()


func _test_hint_reentry(mode: String) -> void:
	var page: Variant = await _open(mode)
	var used: int = tracker.get_stat("hint_used")
	var total: int = game.get_game_total_stat(page._game_type(), "hint_used_total")
	var original: Array = page._board_view.get_board()
	var fired := {"value": false}
	# 同步 durable 通知发生在页面接纳快照前；该阶段的重复点击必须被拒绝。
	var listener := func(_revision: int) -> void:
		if fired.value:
			return
		fired.value = true
		_press(page, "hint")
		_press(page, "hint")
	game.get_core_store().committed.connect(listener)
	_press(page, "hint")
	game.get_core_store().committed.disconnect(listener)
	var saved: Dictionary = _saved(mode)
	_check(fired.value and saved.last_sequence == 1, mode + " commit-time repeated hints cannot submit stale runtime")
	_check(game.get_tool_count("hint") == 4, mode + " one accepted hint charges once")
	_check(tracker.get_stat("hint_used") == used + 1 and game.get_game_total_stat(page._game_type(), "hint_used_total") == total + 1, mode + " counts only the accepted purchase")
	_check(page._hint_token == saved.snapshot.pending_hint.token and page._hint_token.ends_with("/hint#1"), mode + " accepted hint token matches its durable receipt")
	_check(page._hint_overlay.visible and not page._hint_data.is_empty() and page._board_view.get_board() == original, mode + " newest hint is displayed without applying a board change")
	_check(page._business_session._next_sequence == 2, mode + " late result cannot rewind session sequence")
	page._hint_overlay._on_dismiss_btn_pressed()
	_press(page, "hint")
	_check(game.get_tool_count("hint") == 3 and tracker.get_stat("hint_used") == used + 2, mode + " explicit subsequent opening still purchases a new hint")
	_check(page._hint_token == _saved(mode).snapshot.pending_hint.token and page._business_session._next_sequence == 3, mode + " next normal action preserves receipt/token agreement")
	page._hint_overlay._on_dismiss_btn_pressed()


func _test_locate_reentry(mode: String) -> void:
	var page: Variant = await _open(mode)
	var used: int = tracker.get_stat("locate_used")
	var total: int = game.get_game_total_stat(page._game_type(), "locate_used_total")
	var fired := {"value": false}
	var listener := func(_revision: int) -> void:
		if fired.value:
			return
		fired.value = true
		_press(page, "locate")
	game.get_core_store().committed.connect(listener)
	_press(page, "locate")
	game.get_core_store().committed.disconnect(listener)
	var saved: Dictionary = _saved(mode)
	_check(fired.value and saved.last_sequence == 1 and game.get_tool_count("locate") == 4, mode + " repeated locate receipt charges only once")
	_check(tracker.get_stat("locate_used") == used + 1 and game.get_game_total_stat(page._game_type(), "locate_used_total") == total + 1, mode + " repeated locate receipt counts only once")
	_check(saved.snapshot.history.size() == 1 and page._business_history.duplicate(true) == saved.snapshot.history, mode + " repeated locate cannot append duplicate local history")
	_check(page._board_view.get_board() == saved.snapshot.board, mode + " locate local board matches durable board")
	_press(page, "locate")
	saved = _saved(mode)
	_check(saved.last_sequence == 2 and game.get_tool_count("locate") == 3 and tracker.get_stat("locate_used") == used + 2, mode + " next independent locate still succeeds once")
	_check(saved.snapshot.history.size() == 2 and page._business_history.duplicate(true) == saved.snapshot.history and page._board_view.get_board() == saved.snapshot.board, mode + " next locate cannot persist duplicate history from first result")


func _test_failure_retry(mode: String) -> void:
	var page: Variant = await _open(mode)
	for kind: String in ["hint", "locate"]:
		var before: Dictionary = game.get_core_store().snapshot()
		var history: Array = page._business_history.duplicate(true)
		var board: Array = page._board_view.get_board()
		var used: int = tracker.get_stat(kind + "_used")
		var total: int = game.get_game_total_stat(page._game_type(), kind + "_used_total")
		var sequence: int = page._business_session._next_sequence
		var injection := {"hits": 0}
		files.set_fault_injector_for_tests(func(phase: String) -> bool:
			if phase == "before_replace":
				injection.hits += 1
				return true
			return false
		)
		_press(page, kind)
		files.set_fault_injector_for_tests(Callable())
		_check(injection.hits > 0, mode + " " + kind + " fault reaches replace boundary")
		_check(game.get_core_store().snapshot() == before and page._business_session._next_sequence == sequence, mode + " failed " + kind + " does not commit or advance sequence")
		_check(tracker.get_stat(kind + "_used") == used and game.get_game_total_stat(page._game_type(), kind + "_used_total") == total, mode + " failed " + kind + " publishes no successful-use statistic")
		_check(page._board_view.get_board() == board and page._business_history.duplicate(true) == history, mode + " failed " + kind + " leaves local gameplay unchanged")
		_press(page, kind)
		_check(game.get_tool_count(kind) == 4 and page._business_session._next_sequence == sequence + 1, mode + " successful " + kind + " retry debits and advances once")
		_check(tracker.get_stat(kind + "_used") == used + 1 and game.get_game_total_stat(page._game_type(), kind + "_used_total") == total + 1, mode + " successful " + kind + " retry counts once")
		if kind == "hint":
			_check(page._hint_token == _saved(mode).snapshot.pending_hint.token, mode + " retry displays the committed hint token")
			page._hint_overlay._on_dismiss_btn_pressed()


func _test_hidden_result(mode: String, kind: String) -> void:
	var page: Variant = await _open(mode)
	var generation: int = page._business_generation
	var used: int = tracker.get_stat(kind + "_used")
	var total: int = game.get_game_total_stat(page._game_type(), kind + "_used_total")
	var after_hide := {}
	var fired := {"value": false}
	var listener := func(_revision: int) -> void:
		if fired.value:
			return
		fired.value = true
		ui.hide_ui(mode)
		after_hide["token"] = page._hint_token
		after_hide["overlay"] = page._hint_overlay.visible
		after_hide["board"] = page._board_view.get_board()
		after_hide["history"] = page._business_history.duplicate(true)
	game.get_core_store().committed.connect(listener)
	_press(page, kind)
	game.get_core_store().committed.disconnect(listener)
	_check(fired.value and page._business_generation > generation and not page.visible, mode + " " + kind + " listener closes the current presentation")
	_check(page._hint_token == after_hide.token and page._hint_overlay.visible == after_hide.overlay, mode + " closed page cannot regain hint UI from old " + kind + " result")
	_check(page._board_view.get_board() == after_hide.board and page._business_history.duplicate(true) == after_hide.history, mode + " old " + kind + " cannot change board/history after hide cleanup")
	_check(game.get_tool_count(kind) == 4 and _saved(mode).last_sequence == 1, mode + " hiding after successful " + kind + " does not undo committed purchase")
	_check(tracker.get_stat(kind + "_used") == used + 1 and game.get_game_total_stat(page._game_type(), kind + "_used_total") == total + 1, mode + " hidden same-round " + kind + " purchase is still counted once")


func _test_failed_then_reentrant_success(mode: String, kind: String) -> void:
	var page: Variant = await _open(mode)
	var used: int = tracker.get_stat(kind + "_used")
	var total: int = game.get_game_total_stat(page._game_type(), kind + "_used_total")
	var injection := {"hits": 0}
	var retried := {"value": false}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			injection.hits += 1
			return true
		return false
	)
	var listener := func(_failure: Dictionary) -> void:
		if retried.value:
			return
		retried.value = true
		files.set_fault_injector_for_tests(Callable())
		_press(page, kind)
	game.storage_failed.connect(listener)
	_press(page, kind)
	game.storage_failed.disconnect(listener)
	files.set_fault_injector_for_tests(Callable())
	_check(_saved(mode).last_sequence == 0 and game.get_tool_count(kind) == 5, mode + " synchronous failure listener cannot submit while the first command owns its runtime")
	_check(tracker.get_stat(kind + "_used") == used and game.get_game_total_stat(page._game_type(), kind + "_used_total") == total, mode + " rejected nested retry publishes no successful statistics")
	_press(page, kind) # 原调用返回后，新请求才可以用当前快照重试。
	var saved: Dictionary = _saved(mode)
	_check(injection.hits == 1 and retried.value, mode + " failed " + kind + " synchronously retries at storage failure")
	_check(saved.last_sequence == 1 and game.get_tool_count(kind) == 4, mode + " reentrant " + kind + " retry commits and charges once")
	_check(tracker.get_stat(kind + "_used") == used + 1 and game.get_game_total_stat(page._game_type(), kind + "_used_total") == total + 1, mode + " stale failure does not duplicate successful " + kind + " statistics")
	_check(not page._business_action_in_flight, mode + " failure and explicit retry both release their command guard")
	if kind == "hint":
		_check(page._hint_overlay.visible and page._hint_token == saved.snapshot.pending_hint.token, mode + " stale failure leaves successful hint visible and applicable")
		page._hint_overlay._on_dismiss_btn_pressed()
	else:
		_check(page._board_view.get_board() == saved.snapshot.board and page._business_history.duplicate(true) == saved.snapshot.history and saved.snapshot.history.size() == 1, mode + " stale failure leaves successful locate board/history intact")


func _test_reopened_page(kind: String) -> void:
	var page: Variant = await _open("game")
	var generation: int = page._business_generation
	var old_game_id: String = game.get_persisted_game_id(page._game_type())
	var next := {}
	var fired := {"value": false}
	var listener := func(_revision: int) -> void:
		if fired.value:
			return
		fired.value = true
		game.set_current_level(51)
		var reopened: Variant = ui.show_ui("game", {"level_index": 51})
		next["same_page"] = reopened == page
		next["token"] = page._hint_token
		next["overlay"] = page._hint_overlay.visible
		next["board"] = page._board_view.get_board()
		next["history"] = page._business_history.duplicate(true)
		next["hint_used"] = tracker.get_stat("hint_used")
		next["locate_used"] = tracker.get_stat("locate_used")
	game.get_core_store().committed.connect(listener)
	_press(page, kind)
	game.get_core_store().committed.disconnect(listener)
	_check(fired.value and next.same_page and page._business_generation > generation and page._level_config.level == 51, "same cached page begins a new level during " + kind + " commit")
	_check(page._hint_token == next.token and page._hint_overlay.visible == next.overlay, "old " + kind + " result cannot put a hint in the new presentation")
	_check(page._board_view.get_board() == next.board and page._business_history.duplicate(true) == next.history, "old " + kind + " result cannot alter new-level board/history")
	await _wait_ready(page)
	_check(page._is_round_entry_ready(), "new level remains playable after stale " + kind + " result")
	# show_ui 返回时入场还在等布局帧；只有新局提交后才有新的 game_id 和统计归属。
	_check(game.get_persisted_game_id(page._game_type()) != old_game_id and tracker.get_stat("hint_used") == 0 and tracker.get_stat("locate_used") == 0, "old " + kind + " result does not increment committed new-level use statistics")
	_press(page, "locate")
	_check(page._board_view.get_board() == _saved("game").snapshot.board and page._business_history.duplicate(true) == _saved("game").snapshot.history, "new-level action after stale " + kind + " result agrees with durable state")


func _test_board_signal_reentry(reopen: bool) -> void:
	var page: Variant = await _open("game")
	var fired := {"value": false}
	var nested := {}
	var listener := func(_row: int, _col: int, _state: int, _source: int) -> void:
		if fired.value:
			return
		fired.value = true
		if reopen:
			game.set_current_level(51)
			ui.show_ui("game", {"level_index": 51})
		else:
			_press(page, "hint")
		nested["board"] = page._board_view.get_board()
		nested["history"] = page._business_history.duplicate(true)
		nested["token"] = page._hint_token
		nested["hint_used"] = tracker.get_stat("hint_used")
		nested["locate_used"] = tracker.get_stat("locate_used")
	page._board_view.cell_state_changed.connect(listener)
	_press(page, "locate")
	page._board_view.cell_state_changed.disconnect(listener)
	_check(fired.value, "locate emits real board change before nested " + ("new level" if reopen else "hint"))
	if reopen:
		_check(page._level_config.level == 51 and page._board_view.get_board() == nested.board and page._business_history.duplicate(true) == nested.history, "locate stops publishing after cell listener opens new level")
		_check(page._hint_token == nested.token and tracker.get_stat("hint_used") == nested.hint_used and tracker.get_stat("locate_used") == nested.locate_used, "partly presented old locate does not change new-level token or stats")
	else:
		var saved: Dictionary = _saved("game")
		_check(saved.last_sequence == 2 and game.get_tool_count("hint") == 4 and game.get_tool_count("locate") == 4, "cell listener submits a separate successful hint after locate")
		_check(saved.snapshot.history.size() == 1 and page._business_history.duplicate(true) == saved.snapshot.history, "nested hint observes complete locate history, not an unfinished local step")
		_check(page._board_view.get_board() == saved.snapshot.board and page._hint_token == saved.snapshot.pending_hint.token, "nested hint retains its valid token and the located board")
		page._hint_overlay._on_dismiss_btn_pressed()
	await _wait_ready(page)
	_press(page, "locate")
	_check(page._board_view.get_board() == _saved("game").snapshot.board and page._business_history.duplicate(true) == _saved("game").snapshot.history, "subsequent locate remains consistent after cell-signal reentry")


func _test_cross_mode_publication(kind: String) -> void:
	var page: Variant = await _open("game")
	var game_type: String = page._game_type()
	var game_id: String = game.get_persisted_game_id(game_type)
	var used: int = int(game.get_game_round_stats(game_type).get(kind + "_used", 0))
	var total: int = game.get_game_total_stat(game_type, kind + "_used_total")
	var switched := {}
	var listener := func(_revision: int) -> void:
		if not switched.is_empty():
			return
		switched["started"] = true
		switched["page"] = ui.show_ui("daily_game")
	game.get_core_store().committed.connect(listener)
	_press(page, kind)
	game.get_core_store().committed.disconnect(listener)
	_check(switched.has("page") and game.get_persisted_game_id(game_type) == game_id, "opening daily during " + kind + " preserves main game identity")
	_check(int(game.get_game_round_stats(game_type).get(kind + "_used", 0)) == used + 1 and game.get_game_total_stat(game_type, kind + "_used_total") == total + 1, "late " + kind + " success belongs to main statistics after active mode switches")
	_check(tracker.get_stat(kind + "_used") == 0, "main " + kind + " cannot increment preparing daily statistics")
	await _wait_ready(switched.page)
	_check(switched.page._is_round_entry_ready() and tracker.get_stat(kind + "_used") == 0 and int(game.get_game_round_stats("daily").get(kind + "_used", 0)) == 0, "committed daily round starts without main " + kind + " use")
	_check(int(game.get_game_round_stats(game_type).get(kind + "_used", 0)) == used + 1, "daily entry preserves the late successful main " + kind + " count")


func _test_multi_cell_hint_publication() -> void:
	var page: Variant = await _open("game")
	var size: int = page._level_config.size
	var cat_col: int = -1
	for col: int in size:
		if page._puzzle.solution[0][col]:
			cat_col = col
	for row: int in size:
		for col: int in size:
			page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT if row == 0 and col == cat_col else CellState.EMPTY)
	page._board_view.refresh_from_model()
	page._business_history = []
	page._reset_all_touch_strokes()
	page._business_highlight_cursor = -2 # 上一次回顾已耗尽；新增实际一步必须重新允许从最新步回顾。
	_press(page, "hint")
	var first_token: String = page._hint_token
	_check(page._hint_data.get("strategy") == "R1_mark" and page._hint_data.get("unit_cells", []).size() > 1, "real hint engine selects a multi-cell mark around a placed cat")
	_check(_saved("game").snapshot.highlight_cursor == -2, "requesting a hint alone preserves the exhausted highlight cursor")
	if page._hint_data.get("strategy") != "R1_mark":
		return
	var observed := {"calls": 0}
	var listener := func(_row: int, _col: int, _state: int, _source: int) -> void:
		observed.calls += 1
		if observed.calls != 1:
			return
		var applied: Dictionary = _saved("game")
		_check(applied.last_receipt.changes.size() > 1, "apply commits multiple cell changes in one receipt")
		_check(page._board_view.get_board() == applied.snapshot.board and page._business_history.duplicate(true) == applied.snapshot.history and applied.snapshot.history.size() == 1, "first apply cell signal already observes the complete committed board and history")
		_press(page, "hint")
	page._board_view.cell_state_changed.connect(listener)
	page._on_hint_applied()
	page._board_view.cell_state_changed.disconnect(listener)
	var saved: Dictionary = _saved("game")
	_check(observed.calls > 0 and saved.last_sequence == 3 and game.get_tool_count("hint") == 3, "multi-cell application allows one independent new hint without charging apply")
	_check(page._hint_overlay.visible and not page._hint_data.is_empty() and page._hint_token != first_token and page._hint_token == saved.snapshot.pending_hint.token, "old apply cleanup cannot erase the new hint requested by its cell listener")
	_check(page._board_view.get_board() == saved.snapshot.board and page._business_history.duplicate(true) == saved.snapshot.history and saved.snapshot.history.size() == 1, "nested new hint retains all multi-cell changes and exactly one undo step")
	_check(page._business_highlight_cursor == -1 and saved.snapshot.highlight_cursor == -1, "new committed hint step resets both local and durable highlight cursors")
	page._hint_overlay._on_dismiss_btn_pressed()
	page._gameplay_policy.undo_mode = "highlight"
	game.set_tool_count("undo", 2)
	# Undo 已从 1.22 UI 移除；仅保留旧存档/独立用例的兼容历史游标合同。
	var response: Dictionary = page._execute_business_action("undo", {}, {"undo_cost": 1, "undo_mode": "highlight"})
	_check(response.get("ok", false), "legacy highlight use case remains compatible")
	if response.get("ok", false) and page._claim_business_presentation(response):
		page._accept_business_model(response)
	var highlighted: Dictionary = _saved("game")
	_check(highlighted.last_sequence == 4 and game.get_tool_count("undo") == 1 and page._business_highlight_cursor == 0 and highlighted.snapshot.highlight_cursor == 0, "next highlight undo starts at newly committed latest step and charges once")
	_check(highlighted.last_receipt.result.get("highlight_cells", []) == saved.snapshot.history[-1].cells and page._board_view.get_board() == saved.snapshot.board, "highlight undo selects all cells of new step without changing board")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
