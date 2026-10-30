## 隔离工程内加载实际 GamePage；验证 UI → 用例 → 同一核心存档的接线。
extends SceneTree

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var scene: PackedScene = load("res://products/meowdoku/gameplay/presentation/main/ui/game_page.tscn")
	var page: Variant = scene.instantiate()
	host.add_child(page)
	page.set_process(false)
	page._entry_ready = true # 本用例手工装配题面，跳过真实入场；入场门槛由专门页面回归验证。
	var game: Node = root.get_node("GameState")
	game.set_tool_count("hint", 1)
	var regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
	var solution: Array = [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]]
	page._puzzle = {"regions": regions, "solution": solution}
	page._level_config = {"level": 1, "size": 4, "rank": 1, "seed": 7}
	page._round_policy = {"schema": 1, "draft_unlock_level": 21}
	var colors: Array[int] = [0, 1, 2, 3]
	page._board_view.setup(4, regions, colors, [], true)
	page._board_view.get_board_state().set_cell_state(0, 1, CellState.CAT)
	page._board_view.refresh_from_model()
	page._setup_undo_system()
	var original: Array = page._board_view.get_board()
	_check(page._ensure_business_round().ok, "real page starts independent round")
	var files: RefCounted = game._product_store.files
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var rejected: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(not rejected.ok, "failed disk write rejects paid hint")
	_check(game.get_tool_count("hint") == 1 and page._board_view.get_board() == original, "failure leaves inventory and actual board untouched")
	files.set_fault_injector_for_tests(Callable())
	var requested: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(requested.ok and game.get_tool_count("hint") == 0, "hint consumes final item after durable commit")
	if not requested.ok:
		page.queue_free()
		quit(1)
		return
	var token: String = requested.result.hint_token
	var checkpoint: Dictionary = game.get_endgame_snapshot()
	_check(checkpoint.get("business_round_id") == requested.round_id, "paid receipt and resumable identity are committed together")
	var session_script: Script = load("res://products/meowdoku/gameplay/application/meowdoku_round_session.gd")
	var resumed: RefCounted = session_script.new(game, "main")
	_check(resumed.ensure_started({"board": original, "regions": regions, "solution": solution}, requested.round_id).ok, "new adapter resumes paid hint without page dependency")
	var before_reopen: Dictionary = game.get_core_store().snapshot()
	var viewed_again: Dictionary = resumed.execute("request_hint", {}, {"board": original, "lives": 3}, checkpoint, {"hint_cost": 1})
	_check(not viewed_again.ok and viewed_again.error == "insufficient_items" and game.get_core_store().snapshot() == before_reopen, "reopened hint requires a new item and insufficient balance changes nothing")
	game.set_tool_count("hint", 1)
	before_reopen = game.get_core_store().snapshot()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	viewed_again = resumed.execute("request_hint", {}, {"board": original, "lives": 3}, checkpoint, {"hint_cost": 1})
	_check(not viewed_again.ok and viewed_again.error == "commit_failed" and game.get_core_store().snapshot() == before_reopen, "failed reopened purchase retains its item and earlier hint receipt")
	files.set_fault_injector_for_tests(Callable())
	viewed_again = resumed.execute("request_hint", {}, {"board": original, "lives": 3}, checkpoint, {"hint_cost": 1})
	_check(viewed_again.ok and viewed_again.result.hint_token != token and game.get_tool_count("hint") == 0, "successful reopened purchase debits a new item and issues a fresh token")
	token = viewed_again.result.hint_token
	# 页面重新关联恢复后的同一会话，然后走真实应用按钮入口。
	page._business_session = resumed
	page._hint_token = token
	page._hint_data = viewed_again.result.hint.duplicate(true)
	var before_history: int = page._step_history.size()
	page._on_hint_applied()
	var after: Array = page._board_view.get_board()
	_check(after != original and game.get_tool_count("hint") == 0, "actual apply button changes board without second debit")
	_check(page._step_history.size() == before_history + 1, "actual apply produces one undo step")
	var saved: Dictionary = game.get_endgame_snapshot()
	_check(saved.get("step_history", []).size() == before_history + 1, "same transaction persists undo history before presentation")
	_check(_restore_board(saved, 4) == after, "durable old-format board matches actual board")
	var repeated: Dictionary = resumed.execute("apply_hint", {"hint_token": token}, {"board": after, "lives": 3}, saved)
	_check(repeated.ok and repeated.changes.is_empty(), "repeat apply has no second change")
	_check(game.get_endgame_snapshot().step_history.size() == before_history + 1, "repeat apply does not duplicate persistent undo step")
	game.set_tool_count("undo", 2)
	var undo: Dictionary = page._execute_business_action("undo", {}, {"undo_cost": 1, "undo_mode": "revert"})
	_check(undo.ok and game.get_tool_count("undo") == 1, "undo decision and payment committed together")
	if undo.ok:
		page._step_history.deserialize(undo.result.history)
		page._present_business_changes(undo, 4)
	_check(page._board_view.get_board() == original, "undo keeps cat and reverses hint marks")
	_check(game.get_endgame_snapshot().step_history.is_empty(), "undo history removed durably in same transaction")
	var no_step: Dictionary = page._execute_business_action("undo", {}, {"undo_cost": 1, "undo_mode": "revert"})
	_check(not no_step.ok and game.get_tool_count("undo") == 1, "unavailable undo never charges")
	game.set_tool_count("locate", 2)
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var locate_failed: Dictionary = page._execute_business_action("locate", {}, {"locate_cost": 1})
	_check(not locate_failed.ok and game.get_tool_count("locate") == 2 and page._board_view.get_board() == original, "failed locate commits neither item nor cell")
	files.set_fault_injector_for_tests(Callable())
	var located: Dictionary = page._execute_business_action("locate", {}, {"locate_cost": 1})
	_check(located.ok and game.get_tool_count("locate") == 1, "locate payment succeeds once")
	if located.ok:
		page._present_business_changes(located, 2)
		_check(page._board_view.get_board()[1][3] == CellState.CAT, "locate preserves old region-size then row/column ordering")
		_check(_restore_board(game.get_endgame_snapshot(), 4) == page._board_view.get_board(), "locate result can restore before any presentation callback")
	page._lives = 0
	var attempt_id: String = page._business_settlement_id()
	var failed_round: Dictionary = page._settle_current_main_or_preview(attempt_id, "fail", page._build_failed_retry_params())
	_check(failed_round.ok, "failure settlement commits with host checkpoint")
	var stored_round: Dictionary = game.get_core_store().snapshot().round_services["doku/main"]
	_check(stored_round.status == "active" and stored_round.snapshot.lives == 0, "failed host cannot expose old live state")
	_check(not game.get_retry_puzzle(1).is_empty(), "failure keeps exact retry puzzle in same transaction")
	page._is_complete = true
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page._on_revive_requested({"consume_free_once": true})
	_check(page._lives == 0 and page._is_complete and page._business_attempt_sequence == 0, "failed revive keeps failure UI and attempt identity")
	_check(not game.get_core_store().snapshot().profile.has_used_revive_free, "failed revive does not consume once-only free entitlement")
	files.set_fault_injector_for_tests(Callable())
	page._on_revive_requested({"consume_free_once": true})
	_check(page._lives > 0 and not page._is_complete and page._business_attempt_sequence == 1, "successful revive publishes lives and next attempt together")
	_check(game.get_core_store().snapshot().profile.has_used_revive_free, "free entitlement is consumed with successful revive")
	var revived_checkpoint: Dictionary = game.get_endgame_snapshot()
	_check(revived_checkpoint.get("business_attempt_sequence") == 1 and revived_checkpoint.lives == page._lives, "revive can restore same attempt after process exit")
	var revision: int = game.get_core_store().revision()
	page._on_revive_requested()
	_check(game.get_core_store().revision() == revision and page._business_attempt_sequence == 1, "duplicate revive callback cannot add another attempt")
	var premature: Dictionary = page._settle_current_main_or_preview(page._business_settlement_id(), "win")
	_check(not premature.ok and premature.error == "round_not_won" and game.get_current_level() == 1, "page cannot settle an unfinished board as victory")
	for row: int in 4:
		for col: int in 4:
			page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT if solution[row][col] else CellState.EMPTY)
	page._board_view.refresh_from_model()
	var victory: Dictionary = page._settle_current_main_or_preview(page._business_settlement_id(), "win")
	_check(victory.ok and game.get_current_level() == 2, "revived attempt can finish once")
	_check(game.get_core_store().snapshot().round_services["doku/main"].status == "settled", "product win closes independent host in same commit")
	var closed: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 0})
	_check(not closed.ok, "independent use case rejects commands after product settlement")
	page._business_generation += 1
	page.queue_free()
	await process_frame
	await process_frame
	for mode: String in ["game", "daily_game"]:
		await _test_hint_button_reopen(mode)
	print("GAME USE CASE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


## 实际产品按钮关闭后再打开同一盘面的提示，每次新请求沿用原版计费。
func _test_hint_button_reopen(mode: String) -> void:
	var ui: Node = root.get_node("UIManager")
	var game: Node = root.get_node("GameState")
	var tracker: Node = root.get_node("Tracker")
	ui.hide_all()
	await create_timer(0.4).timeout
	_check(game.reset_all(), mode + " resets the isolated player for real hint buttons")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("hint", 2)
	var ab: Node = root.get_node("ABTestManager")
	ab.reward_unlock_level.set_debug_override(0)
	ab.daily_first_level_difficulty.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	var deadline: int = Time.get_ticks_msec() + 8000
	while page != null and (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page != null and page._is_round_entry_ready() and not page._entry_anim_playing, mode + " reaches a playable actual page")
	if page == null or not page._is_round_entry_ready() or page._entry_anim_playing:
		return
	_check(page._tool_cost("hint") == 1, mode + " uses its paid product policy")
	var original: Array = page._board_view.get_board()
	var used_before: int = tracker.get_stat("hint_used")
	page._tool_hint_btn.pressed.emit()
	await process_frame
	var first_token: String = page._hint_token
	_check(page._hint_overlay.visible and not first_token.is_empty() and game.get_tool_count("hint") == 1, mode + " first real hint request displays and debits once")
	page._hint_overlay._on_close_btn_pressed()
	_check(not page._hint_overlay.visible and page._hint_data.is_empty(), mode + " close dismisses the hint without applying it")
	page._tool_hint_btn.pressed.emit()
	await process_frame
	_check(page._hint_overlay.visible and page._hint_token != first_token and game.get_tool_count("hint") == 0, mode + " reopening the same board is a new paid hint")
	_check(tracker.get_stat("hint_used") == used_before + 2 and page._board_view.get_board() == original, mode + " both requests count as uses without changing the board")
	page._hint_overlay._on_close_btn_pressed()
	# 原有免费策略仍覆盖收费，而不是因为恢复重复购买就把所有请求强制改成付费。
	page.debug_force_free_tool = "hint"
	var second_token: String = page._hint_token
	page._tool_hint_btn.pressed.emit()
	await process_frame
	_check(page._hint_overlay.visible and page._hint_token != second_token and game.get_tool_count("hint") == 0, mode + " explicit free hint policy still permits a new request at zero balance")
	page._hint_overlay._on_close_btn_pressed()
	page.debug_force_free_tool = ""
	ui.hide_all()
	await create_timer(0.4).timeout


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _restore_board(saved: Dictionary, size: int) -> Array:
	var board: Array = []
	for row in size:
		var line: Array = []
		line.resize(size)
		line.fill(CellState.EMPTY)
		board.append(line)
	var fields: Dictionary = {"placed_cats": CellState.CAT, "marks": CellState.MARK, "errors": CellState.ERROR, "locked_marks": CellState.LOCKED_MARK}
	for field: String in fields:
		for position: Array in saved.get(field, []):
			board[int(position[0])][int(position[1])] = fields[field]
	return board
