## 实际页面检查点、延迟回调和恢复策略；只由隔离 validation runner 启动。
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
	var ui: Node = root.get_node("UIManager")
	var game: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(1)
	ab.prop_mouse.set_debug_override(1)
	var level: int = game.get_current_level()
	var page: Variant = ui.show_ui("game", {"level_index": level})
	await create_timer(0.8).timeout
	_check(page != null and page._entry_error.is_empty() and not page._puzzle.is_empty(), "actual main page opens")
	if page == null or page._puzzle.is_empty():
		quit(1)
		return
	page._entry_anim_playing = false
	var before: Dictionary = game.get_endgame_snapshot()
	var positions: Array = _empty_positions(page, 3)
	_check(positions.size() == 3, "fixture has three editable cells")
	if positions.size() != 3:
		quit(1)
		return
	_set_mark(page, positions[0])
	var files: RefCounted = game._product_store.files
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page._flush_endgame_snapshot()
	_check(game.get_endgame_snapshot() == before, "failed checkpoint leaves published persisted snapshot unchanged")
	_check(page._endgame_save_failed and page._endgame_retry_count == 1 and page._endgame_persist_timer.time_left > 0.0, "failed checkpoint schedules bounded retry")
	_check(page._board_view.get_board()[positions[0][0]][positions[0][1]] == CellState.MARK, "failed checkpoint retains live edit")
	for _attempt in range(3):
		page._endgame_persist_timer.stop()
		page._flush_endgame_snapshot()
	_check(page._endgame_retry_count == 3 and page._endgame_persist_timer.is_stopped(), "continuous write failure stops automatic retry after bounded attempts")
	# 重试捕获最新棋盘，不能提交第一次失败时缓存的旧副本。
	_set_mark(page, positions[1])
	files.set_fault_injector_for_tests(Callable())
	page._endgame_persist_timer.stop()
	page._flush_endgame_snapshot()
	var saved: Dictionary = game.get_endgame_snapshot()
	_check(saved.marks.has(positions[0]) and saved.marks.has(positions[1]), "retry saves latest two edits")
	_check(not page._endgame_save_failed and page._endgame_retry_count == 0, "successful retry clears failure state")
	# 模拟已排队、但在窗口新代次才抵达的回调。
	page._board_view.get_board_state().set_cell_state(positions[0][0], positions[0][1], CellState.EMPTY)
	page._flush_endgame_for_generation.call_deferred(page._business_generation)
	page._business_generation += 1
	await process_frame
	_check(game.get_endgame_snapshot() == saved, "old generation deferred callback cannot overwrite current checkpoint")
	_set_mark(page, positions[0])
	page._flush_endgame_snapshot()
	var frozen_policy: Dictionary = page._gameplay_policy_snapshot()
	var frozen_rules: Dictionary = page._round_policy.duplicate(true)
	_check(int(frozen_policy.prop_mouse) == 1, "entry captures selected mouse policy")
	_set_mark(page, positions[2])
	ui.hide_ui("game")
	_check(game.get_endgame_snapshot().marks.has(positions[2]), "closing page commits the final unsaved frame")
	await create_timer(0.35).timeout
	ab.prop_mouse.set_debug_override(0)
	ab.normal_endgame_save.set_debug_override(0)
	page = ui.show_ui("game", {"level_index": level})
	await create_timer(0.8).timeout
	_check(page._gameplay_policy_snapshot() == frozen_policy, "restored game retains previous gameplay policy after AB changes")
	_check(page._round_policy == frozen_rules, "restored game retains previous content rules")
	_check(page._board_view.get_board()[positions[2][0]][positions[2][1]] == CellState.MARK, "restored UI presents the final closing edit")
	_check(page._board_view.get_board()[positions[0][0]][positions[0][1]] == CellState.MARK and page._board_view.get_board()[positions[1][0]][positions[1][1]] == CellState.MARK, "restored UI presents retried durable edits")
	# 普通棋盘落子只更新残局；宿主仍是未完成盘面。恢复已完成残局须同步后结算。
	page._entry_anim_playing = false
	_check(page._ensure_business_round().ok, "restored page establishes durable host identity")
	_complete_board(page)
	page._flush_endgame_snapshot()
	var complete_snapshot: Dictionary = game.get_endgame_snapshot()
	_check(not str(complete_snapshot.get("business_round_id", "")).is_empty(), "completed checkpoint carries host identity")
	ui.hide_ui("game")
	await create_timer(0.35).timeout
	ab.normal_endgame_save.set_debug_override(3)
	game._login_gap_days = 10
	game._stale_endgame_discarded = false
	var stale_gate: Variant = load("res://products/meowdoku/gameplay/presentation/main/stale_endgame_gate.gd")
	_check(stale_gate.is_pending_stale_discard(), "fixture activates stale restart policy before restoring completed checkpoint")
	page = ui.show_ui("game", {"level_index": level})
	await create_timer(0.8).timeout
	_check(game.get_current_level() == level + 1, "complete checkpoint settles despite stale host board")
	_check(page._entry_error.is_empty() and int(page._level_config.get("level", 0)) == level + 1, "complete checkpoint reopens next level")
	game._login_gap_days = 0
	ui.hide_ui("game")
	await create_timer(0.35).timeout
	# 固定关卡奖励不依赖可选残局镜像；用真实页面桥接器建立第二个实例。
	ab.normal_endgame_save.set_debug_override(0)
	game.set_current_level(21)
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile.current_strategy = 3
	candidate.profile.consecutive_fails = 0
	candidate.profile.consecutive_retry_levels = 0
	candidate.profile.retry_tracking_strategy = 0
	candidate.round_runtime.current_level_retried = true
	candidate.round_runtime.demoted_this_level = false
	candidate.round_runtime.current_level_dirty = true
	candidate.round_runtime.dda_tool_or_revive_used = true
	candidate.round_runtime.dda_pending_demote = false
	candidate.round_runtime.is_daily_first_easy_level = false
	candidate.round_runtime.rnr_mod1_exempt = false
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, "DDA fixture commits through actual product store")
	var scene: PackedScene = load("res://products/meowdoku/gameplay/presentation/main/ui/game_page.tscn")
	var fixture: Variant = scene.instantiate()
	host.add_child(fixture)
	fixture.set_process(false)
	fixture._begin_business_entry({})
	var regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
	var solution: Array = [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]]
	var definition: Dictionary = {"puzzle": {"bank": "doku/levels/bankdata4x4", "rank": 1, "index": 1}, "reward": {"hint": 2}}
	fixture._puzzle = {"regions": regions, "solution": solution}
	var selector: Script = load("res://products/meowdoku/gameplay/application/selection/level_selector.gd")
	var saved_selection: Dictionary = selector.capture_context(7).policy.duplicate(true)
	saved_selection.normal_level = 0
	saved_selection.content_policy["special_levels"] = {"22": "frozen-special-fixture"}
	fixture._level_config = {"level": game.get_current_level(), "size": 4, "rank": 1, "seed": 7, "level_definition": definition, "selection_policy": saved_selection}
	fixture._round_policy = {"schema": 1, "draft_unlock_level": 21}
	fixture._freeze_gameplay_policy()
	# 1.22 DDA 由重试事实与冻结 selection_policy 驱动；不以旧四个 gameplay dda 布尔值代替。
	# 保存时的内容把22关标为特殊关，而当前实验/内置表没有这项。
	ab.normal_level.set_debug_override(12100)
	ab.dda_rank.set_debug_override(0)
	var colors: Array[int] = [0, 1, 2, 3]
	fixture._board_view.setup(4, regions, colors, [], true)
	_check(fixture._commit_prepared_round({}), "fixed fixture commits prepared round through actual entry transaction")
	_check(fixture._business_checkpoint().is_empty(), "disabled endgame AB supplies no optional checkpoint")
	_check(fixture._ensure_business_round().ok, "fixed level still starts host without checkpoint")
	var record: Dictionary = game.get_core_store().snapshot().round_services["doku/main"]
	_check(record.snapshot.content.level_definition == definition, "host captures fixed level reward independently of endgame AB")
	_check(record.snapshot.content.selection_policy == saved_selection, "host saves original 1.22 selection experiment and content policy")
	_complete_board(fixture)
	var hint_before: int = game.get_tool_count("hint")
	var level_before: int = game.get_current_level()
	var attempt: String = fixture._business_settlement_id()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed: Dictionary = fixture._settle_current_main_or_preview(attempt, "win")
	_check(not failed.ok and game.get_tool_count("hint") == hint_before and game.get_current_level() == level_before, "failed fixed reward settlement changes neither progress nor inventory")
	files.set_fault_injector_for_tests(Callable())
	var settled: Dictionary = fixture._settle_current_main_or_preview(attempt, "win")
	_check(settled.ok and game.get_tool_count("hint") == hint_before + 2 and game.get_current_level() == level_before + 1, "fixed reward and progress commit together without endgame saving")
	var after_settlement: Dictionary = game.get_core_store().snapshot()
	_check(after_settlement.round_runtime.dda_pending_demote and int(after_settlement.profile.current_strategy) == 3, "1.22 retried win defers demotion at frozen next special level despite different live experiment")
	var repeated: Dictionary = fixture._settle_current_main_or_preview(attempt, "win")
	_check(repeated.ok and repeated.duplicate and game.get_tool_count("hint") == hint_before + 2, "repeated fixed settlement never pays twice")
	fixture._business_generation += 1
	fixture.queue_free()
	await process_frame
	print("PRODUCT CHECKPOINT TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _empty_positions(page: Variant, count: int) -> Array:
	var result: Array = []
	var board: Array = page._board_view.get_board()
	for row: int in board.size():
		for col: int in board[row].size():
			if board[row][col] == CellState.EMPTY and not page._puzzle.solution[row][col]:
				result.append([row, col])
				if result.size() == count:
					return result
	return result


func _set_mark(page: Variant, position: Array) -> void:
	page._board_view.get_board_state().set_cell_state(position[0], position[1], CellState.MARK)
	page._board_view.refresh_from_model()


func _complete_board(page: Variant) -> void:
	var solution: Array = page._puzzle.solution
	for row: int in solution.size():
		for col: int in solution[row].size():
			page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT if solution[row][col] else CellState.EMPTY)
	page._board_view.refresh_from_model()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
