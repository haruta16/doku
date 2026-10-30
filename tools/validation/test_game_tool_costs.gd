## 原版按次收费边界：真实主线/每日按钮与持久宿主，不退回非事务扣库存。
extends SceneTree

const Files = preload("res://scripts/framework/storage/save_store.gd")
const Store = preload("res://scripts/framework/storage/local_core_store.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Module = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var kit: Node
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
	kit = root.get_node("UniKitManager")
	tracker = root.get_node("Tracker")
	files = game.get_core_store().get("_file_store")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.daily_first_level_difficulty.set_debug_override(0)
	ab.reward_unlock_level.set_debug_override(0)
	ab.undo_btn.set_debug_override(1)
	ab.dc_level.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	kit.cheat_show_reward = true
	_test_host_empty_locate()
	for mode: String in ["game", "daily_game"]:
		await _test_empty_locate(mode)
		await _test_undo_boundaries(mode)
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await create_timer(0.7).timeout
	print("GAME TOOL COST TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open(mode: String) -> Variant:
	ui.hide_all()
	await create_timer(0.3).timeout
	_check(game.reset_all(), mode + " resets isolated player")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("locate", 3)
	game.set_tool_count("undo", 3)
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame
	page._last_tool_deplete_ms = -10000
	_check(page._is_round_entry_ready() and not page._entry_anim_playing, mode + " real page entered before tool input")
	_check(page._tool_cost("locate") == 1 and page._tool_cost("undo") == 1, mode + " frozen fixture uses paid tools")
	return page


func _replace_board(page: Variant, filled: bool) -> void:
	var size: int = page._level_config.size
	for row: int in size:
		for col: int in size:
			page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT if filled and page._puzzle.solution[row][col] else CellState.EMPTY)
	page._board_view.refresh_from_model()
	page._step_history.deserialize([])
	page._current_step_cells.clear()
	page._highlight_cursor = -1
	# 模拟最后一只猫已进入活棋盘、页面尚未结算的原版空候选窗口。
	page._is_complete = false
	page._wrong_guess_pending = false


func _test_empty_locate(mode: String) -> void:
	var page: Variant = await _open(mode)
	_replace_board(page, true)
	_check(page._ensure_business_round().get("ok", false), mode + " prepares a durable active round with no locate candidate")
	var before_board: Array = page._board_view.get_board()
	var before_history: Array = page._step_history.serialize()
	var before_feedback: Dictionary = page._like_hand_state.duplicate(true)
	var uses: int = tracker.get_stat("locate_used")
	var totals: int = game.get_game_total_stat(page._game_type(), "locate_used_total")
	page._tool_locate_btn.pressed.emit()
	_check(game.get_tool_count("locate") == 2, mode + " empty locate consumes one item as in the original")
	_check(tracker.get_stat("locate_used") == uses + 1 and game.get_game_total_stat(page._game_type(), "locate_used_total") == totals + 1, mode + " empty locate counts the accepted attempt")
	_check(page._board_view.get_board() == before_board and page._step_history.serialize() == before_history, mode + " empty locate changes neither board nor history")
	_check(page._like_hand_state == before_feedback and not page._is_complete, mode + " empty locate does not fabricate cat feedback or settle the board")
	var state_key: String = "doku/" + ("main" if mode == "game" else "daily")
	var saved: Dictionary = game.get_core_store().snapshot().round_services[state_key]
	_check(saved.last_receipt.result.get("no_effect") == "no_locate_target" and saved.snapshot.board == before_board and saved.snapshot.history == before_history, mode + " empty attempt is durably distinguished from board changes")
	var core_before: Dictionary = game.get_core_store().snapshot()
	uses = tracker.get_stat("locate_used")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page._tool_locate_btn.pressed.emit()
	_check(game.get_tool_count("locate") == 2 and game.get_core_store().snapshot() == core_before, mode + " failed empty-locate save neither debits nor commits")
	_check(tracker.get_stat("locate_used") == uses and page._board_view.get_board() == before_board, mode + " failed save publishes no accepted-use statistic or board change")
	files.set_fault_injector_for_tests(Callable())
	page._tool_locate_btn.pressed.emit()
	_check(game.get_tool_count("locate") == 1 and tracker.get_stat("locate_used") == uses + 1, mode + " retry after failed empty locate charges exactly once")
	page.debug_force_free_tool = "locate"
	page._sync_tools_from_state()
	page._tool_locate_btn.pressed.emit()
	_check(game.get_tool_count("locate") == 1 and tracker.get_stat("locate_used") == uses + 2, mode + " free empty locate counts its attempt without a debit")
	page.debug_force_free_tool = ""
	game.set_tool_count("locate", 0)
	page._sync_tools_from_state()
	page._last_tool_deplete_ms = -10000
	uses = tracker.get_stat("locate_used")
	var sequence: int = game.get_core_store().snapshot().round_services[state_key].last_sequence
	page._tool_locate_btn.pressed.emit()
	var show_id: String = kit._reward_active_show_id
	_check(not show_id.is_empty() and kit._reward_callbacks.has(show_id), mode + " empty inventory requests an ad even when there is no locate target")
	_check(game.get_tool_count("locate") == 0 and tracker.get_stat("locate_used") == uses and game.get_core_store().snapshot().round_services[state_key].last_sequence == sequence, mode + " ad request is not a paid tool attempt")
	var mock: Variant = ui.get_ui("mock_ad")
	_check(mock != null and mock.is_showing(), mode + " real mock ad opens")
	if mock != null:
		mock._on_close_pressed()
		await create_timer(0.1).timeout
	kit._on_ad_rewarded_for_show("reward", show_id)
	_check(game.get_tool_count("locate") == 1 and tracker.get_stat("locate_used") == uses, mode + " ad reward adds an item without automatically using it")
	_check(page._board_view.get_board() == before_board and page._step_history.serialize() == before_history and not page._is_complete, mode + " rewarded ad does not fabricate a locate result")
	page._last_tool_deplete_ms = -10000
	page._tool_locate_btn.pressed.emit()
	_check(game.get_tool_count("locate") == 0 and tracker.get_stat("locate_used") == uses + 1, mode + " explicit click after reward consumes the granted item")
	var balance: int = game.get_tool_count("locate")
	page._is_complete = true
	page._tool_locate_btn.pressed.emit()
	_check(game.get_tool_count("locate") == balance and kit._reward_active_show_id.is_empty(), mode + " actually completed page still blocks tool use and ads")


func _test_undo_boundaries(mode: String) -> void:
	var page: Variant = await _open(mode)
	_replace_board(page, false)
	_check(page._ensure_business_round().get("ok", false), mode + " undo fixture has a durable round")
	page._tool_undo_btn.pressed.emit()
	_check(game.get_tool_count("undo") == 3, mode + " empty history remains free as in the original")
	page._step_history.deserialize([{"cells": [[0, 0, CellState.EMPTY, CellState.MARK]], "cat": false, "wrong": false}])
	var board: Array = page._board_view.get_board()
	var core_before: Dictionary = game.get_core_store().snapshot()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page._tool_undo_btn.pressed.emit()
	_check(game.get_tool_count("undo") == 3 and page._step_history.size() == 1 and game.get_core_store().snapshot() == core_before, mode + " failed selected-undo save keeps item and history")
	files.set_fault_injector_for_tests(Callable())
	page._tool_undo_btn.pressed.emit()
	_check(game.get_tool_count("undo") == 2 and page._step_history.size() == 0 and page._board_view.get_board() == board, mode + " selected unchanged step consumes once and removes history")
	page._tool_undo_btn.pressed.emit()
	_check(game.get_tool_count("undo") == 2, mode + " newly exhausted history does not consume again")
	page._board_view.get_board_state().set_cell_state(0, 0, CellState.CAT)
	page._board_view.refresh_from_model()
	page._step_history.deserialize([{"cells": [[0, 0, CellState.EMPTY, CellState.CAT]], "cat": true, "wrong": false}])
	page._tool_undo_btn.pressed.emit()
	_check(game.get_tool_count("undo") == 2 and page._step_history.size() == 1, mode + " protected-only history still has no payable undo target")
	page._gameplay_policy.undo_mode = "highlight"
	page._highlight_cursor = -2
	page._tool_undo_btn.pressed.emit()
	_check(game.get_tool_count("undo") == 2 and page._highlight_cursor == -2, mode + " exhausted highlight is not charged")


func _test_host_empty_locate() -> void:
	var directory: String = "user://tool-cost-host-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var disk := Files.new("tool-cost-only", directory, true, directory + "/a", directory + "/b", directory + "/flag")
	var store := Store.new(disk, 1)
	_check(store.open({"inventory": {"locate": 3}, "round_services": {}}).ok, "isolated host store opens")
	var host := Host.new(store)
	_check(host.register_module("doku", Module.new()), "isolated host registers Doku")
	var board: Array = [[0, CellState.CAT, 0, 0], [0, 0, 0, CellState.CAT], [CellState.CAT, 0, 0, 0], [0, 0, CellState.CAT, 0]]
	var regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
	var solution: Array = [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]]
	var started: Dictionary = host.start("doku", "main", 1, {"board": board, "regions": regions, "solution": solution, "lives": 3})
	_check(started.ok, "isolated host keeps solved but unsettled round active")
	if not started.ok:
		return
	var first: Dictionary = host.action("doku", "main", started.round_id, 1, "locate", {}, {}, {"locate_cost": 1})
	_check(first.ok and first.result.get("no_effect") == "no_locate_target" and first.changes.is_empty() and store.snapshot().inventory.locate == 2, "host records one payable empty attempt")
	var before: Dictionary = store.snapshot()
	var repeated: Dictionary = host.action("doku", "main", started.round_id, 1, "locate", {}, {}, {"locate_cost": 1})
	_check(repeated.get("duplicate", false) and store.snapshot() == before, "same empty-attempt sequence cannot charge twice")
	disk.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var rejected: Dictionary = host.action("doku", "main", started.round_id, 2, "locate", {}, {}, {"locate_cost": 1})
	_check(not rejected.ok and rejected.error == "commit_failed" and store.snapshot() == before, "failed new empty attempt leaves sequence and balance intact")
	disk.set_fault_injector_for_tests(Callable())
	var retry: Dictionary = host.action("doku", "main", started.round_id, 2, "locate", {}, {}, {"locate_cost": 1})
	_check(retry.ok and store.snapshot().inventory.locate == 1 and retry.snapshot.board == board and retry.snapshot.board_revision == 0, "retry charges once without changing board revision")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
