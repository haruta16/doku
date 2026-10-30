## 1.22真实页面：入口候选、失败扣费、提示、草稿、生命周期与恢复。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var fault_hits: int = 0
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
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	files = game.get_core_store().get("_file_store")
	_check(game.reset_all(), "isolated player resets")
	game.set_sound_on(false)
	game.set_music_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(31)
	game.set_tool_count("hint", 20)
	game.set_tool_count("locate", 20)
	game.set_tool_count("mouse", 20)
	game.set_tool_count("draft", 20)
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(1)
	var before: Dictionary = game.get_core_candidate()
	_fail_writes(true)
	var page: Variant = ui.show_ui("game", {"level_index": 31})
	await create_timer(0.4).timeout
	_check(fault_hits > 0, "entry failure reaches injected before_replace storage fault")
	_check(page._entry_error.get("error") != "selection_conflict", "entry failure is not unrelated candidate conflict")
	_check(page != null and not page._entry_ready, "failed initial commit never opens board")
	_check(not page._entry_error.is_empty(), "failed entry has a retriable result")
	_check(game.get_core_candidate().profile.bank_progress == before.profile.bank_progress, "failed selection retains all bank cursors")
	_check(game.get_core_candidate().profile.retry_puzzle_params == before.profile.retry_puzzle_params, "failed selection retains retry data")
	_check(not page._execute_business_action("request_hint").get("ok", false), "failed entry cannot charge a delayed tool")
	_fail_writes(false)
	await _close()
	page = ui.show_ui("game", {"level_index": 31})
	await _wait_ready(page)
	_check(page._entry_ready, "retry commits real 1.22 entry")
	if not page._entry_ready:
		_finish()
		return
	_check(not page._business_session.round_id().is_empty(), "initial entry already owns durable round")
	_check(not page._level_config.get("selection_policy", {}).is_empty(), "entry freezes complete selection policy")
	_check(game.get_endgame_snapshot().get("regionMap") == page._puzzle.regions, "initial checkpoint matches prepared board")
	page._entry_anim_playing = false
	page._tool_btns_locked = false
	var hint_before: int = game.get_tool_count("hint")
	var hint_cost: int = page._tool_cost("hint")
	_fail_writes(true)
	page._on_hint_btn_pressed()
	_check(game.get_tool_count("hint") == hint_before, "failed hint commit leaves inventory unchanged")
	_check(page._hint_token.is_empty() and not page._hint_overlay.visible, "failed hint has neither token nor visible hint")
	_fail_writes(false)
	page._on_hint_btn_pressed()
	_check(game.get_tool_count("hint") == hint_before - hint_cost, "real hint handler consumes exactly committed cost")
	_check(not page._hint_token.is_empty() and page._hint_overlay.visible, "paid/free hint publishes token only after commit")
	if not page._hint_token.is_empty():
		page._on_hint_applied()
		_check(page._business_session.round_id() == str(game.get_endgame_snapshot().get("business_round_id", "")), "hint action and checkpoint use same durable identity")
		_check(page._board_view.get_board() == game.get_core_candidate().round_services["doku/main"].snapshot.board, "applied hint publishes committed full board")
	await create_timer(1.0).timeout
	page._hint_cooldown = false
	page._entry_anim_playing = false
	page._tool_btns_locked = false
	var activated: Dictionary = page._execute_business_action("activate_draft", {}, {"enabled": true, "cost": 1, "level": 31})
	_check(activated.get("ok", false), "draft activation is an ordinary durable action")
	if activated.get("ok", false):
		page._accept_business_model(activated)
		page._enter_draft_mode(false)
		var empty_cell := Vector2i(-1, -1)
		var board: Array = page._board_view.get_board()
		for r: int in board.size():
			for c: int in board[r].size():
				if int(board[r][c]) == CellState.EMPTY and empty_cell.x < 0:
					empty_cell = Vector2i(r, c)
		if empty_cell.x >= 0:
			page._set_cell_draft(empty_cell.x, empty_cell.y, CellState.DRAFT_CROSS)
		var draft_before: Array = page._board_view.get_board().duplicate(true)
		_fail_writes(true)
		page._exit_draft_mode_and_clear()
		_check(page._draft_mode and page._board_view.get_board() == draft_before, "failed draft exit keeps activation and draft marks retryable")
		_fail_writes(false)
		page._exit_draft_mode_and_clear()
		_check(not page._draft_mode, "successful draft exit clears presentation activation")
		_check(not game.get_core_candidate().round_services["doku/main"].snapshot.draft_active, "draft exit clears durable activation in same action")
	var generation: int = page._business_generation
	ui.hide_ui("game")
	await create_timer(0.4).timeout
	_check(page._business_generation != generation and not page._entry_ready, "hide invalidates business generation")
	var inventory: Dictionary = game.get_core_candidate().inventory.duplicate(true)
	page._on_hint_btn_pressed()
	page._on_locate_btn_pressed()
	page._try_start_mouse_tool()
	_check(game.get_core_candidate().inventory == inventory, "hidden page handlers cannot charge inventory")
	var old_round: String = page._business_session.round_id()
	page = ui.show_ui("game", {"level_index": 31})
	await _wait_ready(page)
	_check(page._entry_ready, "checkpoint re-entry remains usable")
	_check(page._business_session.round_id() == old_round, "checkpoint restore keeps business round identity")
	page = await _test_score_interruption_and_win(page)
	await _close()
	_finish()

func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while not page._entry_ready and page._entry_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame

func _close() -> void:
	ui.hide_ui("game")
	await create_timer(0.4).timeout

func _fail_writes(enabled: bool) -> void:
	if not enabled:
		files.set_fault_injector_for_tests(Callable())
		return
	fault_hits = 0
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			fault_hits += 1
			return true
		return false
	)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)

func _finish() -> void:
	_fail_writes(false)
	ui.hide_all()
	for name: String in ["game", "daily_game", "confirm"]:
		await ui.destroy_ui(name)
	await process_frame
	await process_frame
	print("GAME 1.22 TRANSACTION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_score_interruption_and_win(page: Variant) -> Variant:
	page._entry_anim_playing = false
	page._tool_btns_locked = false
	page._hint_cooldown = false
	# 仅留下答案猫，让1.22鼠标走补猫分支，分数不得依赖接下来的动画。
	var board: Array = page._board_view.get_board()
	for row: int in board.size():
		for col: int in board[row].size():
			if not page._puzzle.solution[row][col]:
				board[row][col] = CellState.MARK
	page._board_view.get_board_state().apply_committed_board(board, Time.get_ticks_msec())
	var old: Dictionary = game.get_core_candidate()
	var runtime: Dictionary = page._business_runtime()
	var payload: Dictionary = {"seed": 122}
	var policy: Dictionary = {"enabled": true, "cost": 1, "level": 31}
	_fail_writes(true)
	var failed: Dictionary = page._execute_business_action("mouse", payload, policy)
	_check(not failed.get("ok", false) and game.get_core_candidate() == old, "failed paid score commit changes neither score, inventory, board nor stats")
	_fail_writes(false)
	var nested: Dictionary = {}
	var reenter: Callable = func(kind: String, _count: int) -> void:
		if kind == "mouse":
			nested.merge(page._execute_business_action("request_hint"), true)
	game.tool_count_changed.connect(reenter)
	var score_before: int = page._score_model.score
	var used: Dictionary = page._execute_business_action("mouse", payload, policy)
	game.tool_count_changed.disconnect(reenter)
	_check(used.get("ok", false), "mouse cat commits through actual page bridge")
	_check(nested.get("error") == "action_in_flight", "synchronous inventory callback cannot reenter a second page action")
	if not used.get("ok", false):
		return page
	page._accept_business_model(used)
	_check(page._score_model.score > score_before and page._score_model.score == used.snapshot.performance.score, "page accepts authoritative mouse score before first animation callback")
	_check(not used.result.performance_events.is_empty() and used.result.performance_events[0].has("row"), "page receives normalized per-cat score animation data")
	var committed: Dictionary = game.get_core_candidate()
	_check(committed.endgame.snapshot.score == used.snapshot.performance.score, "legacy checkpoint and canonical record contain the same paid score")
	var repeated: Dictionary = page._business_session._host.action("doku", "main", str(used.round_id), int(used.sequence), "mouse", payload, runtime, policy)
	_check(repeated.get("duplicate", false) and game.get_core_candidate() == committed, "retrying exact paid score action cannot add score, usage or deduct inventory twice")
	var round_id: String = page._business_session.round_id()
	var performance: Dictionary = used.snapshot.performance.duplicate(true)
	# 不发送cell_state_changed、不运行鼠标动画，直接模拟离场和恢复。
	await _close()
	page = ui.show_ui("game", {"level_index": 31})
	await _wait_ready(page)
	_check(page._entry_ready and page._business_session.round_id() == round_id, "interrupted mouse presentation restores the same durable round")
	_check(page._score_model.score == performance.score and page._se_count == performance.se_count, "interrupted mouse presentation restores paid score and combo facts")
	_check(root.get_node("Tracker").get_stat("step_used") == performance.step_used, "restored tracker step cache matches the committed action")
	# 真页面的终局适配器与排行榜使用同一候选：先注入保存失败，再重试及去重。
	var rank_candidate: Dictionary = game.get_core_candidate()
	var rank: Dictionary = rank_candidate.features.get("rank_activity", {}).duplicate(true)
	rank.merge({"state": 2, "joined": true, "period_count": 1, "group": 1, "start_unix": int(Time.get_unix_time_from_system()), "end_unix": int(Time.get_unix_time_from_system()) + 86400, "settled": false, "collect_total": 10}, true)
	rank_candidate.features["rank_activity"] = rank
	_check(game.commit_core_candidate(rank_candidate, game.get_core_store().revision()).ok, "active rank fixture commits through the same product store")
	board = page._board_view.get_board()
	for row: int in board.size():
		for col: int in board[row].size():
			board[row][col] = CellState.CAT if page._puzzle.solution[row][col] else CellState.MARK
	page._board_view.get_board_state().apply_committed_board(board, Time.get_ticks_msec())
	var attempt: String = page._business_settlement_id()
	var before_win: Dictionary = game.get_core_candidate()
	_fail_writes(true)
	var failed_win: Dictionary = page._settle_current_main_or_preview(attempt, "win")
	_check(not failed_win.get("ok", false) and game.get_core_candidate() == before_win, "failed real main win leaves progression, rank, inventory and receipt wholly unchanged")
	_fail_writes(false)
	var won: Dictionary = page._settle_current_main_or_preview(attempt, "win")
	_check(won.get("ok", false) and game.get_current_level() == 32, "real main win advances level exactly once")
	var after_win: Dictionary = game.get_core_candidate()
	_check(int(after_win.features.rank_activity.collect_total) > 10, "real main win commits rank collection in the same transaction")
	var duplicate_win: Dictionary = page._settle_current_main_or_preview(attempt, "win")
	_check(duplicate_win.get("duplicate", false) and game.get_core_candidate() == after_win, "main win retry cannot repeat rank collection or rewards")
	page._is_complete = true
	return page
