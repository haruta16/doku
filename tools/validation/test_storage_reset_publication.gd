## 同步提交通知可清档；旧结算的会话副作用不能重新写入重置后的产品状态。
extends SceneTree
const RoundHost = preload("res://scripts/framework/application/round_service.gd")
const DokuModule = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
var game: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	game = root.get_node("GameState")
	for mode: String in ["main", "daily", "preview"]:
		for outcome: String in ["win", "fail", "quit"]:
			_test_settlement_reset(mode, outcome)
	_test_failed_reset_reentered()
	_test_successful_reset_reentered()
	print("STORAGE RESET PUBLICATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_settlement_reset(mode: String, outcome: String) -> void:
	_check(game.reset_all(), "prepare isolated reset fixture")
	game.set_current_level(2)
	var host := RoundHost.new(game.get_core_store())
	host.register_module("doku", DokuModule.new())
	var records: Dictionary = game.get_core_store().snapshot().round_services
	var sequence: int = int(records.get("doku/" + mode, {}).get("start_sequence", 0)) + 1
	var started: Dictionary = host.start("doku", mode, sequence, {"board": [[0]], "regions": [[0]], "solution": [[true]], "content": {"level": 2 if mode == "main" else 0}})
	_check(started.ok, "actual host starts " + mode)
	var state := {"called": false, "reset": false}
	var listener := func(_revision: int) -> void:
		if state.called or not game.get_core_store().snapshot().get("product_settlements", {}).has(mode):
			return
		state.called = true
		state.reset = game.reset_all()
	game.get_core_store().committed.connect(listener)
	var result: Dictionary
	var id: String = str(started.round_id) + "/attempt#0"
	match mode:
		"main": result = game.settle_main_round(id, 2, outcome, {"board": [[1 if outcome == "win" else 0]], "lives": 0 if outcome == "fail" else 3})
		"daily": result = game.settle_daily_round(id, Time.get_date_string_from_system(), outcome, 12, 88.0, {"board": [[1 if outcome == "win" else 0]], "lives": 0 if outcome == "fail" else 3})
		_: result = game.settle_preview_round(id, outcome, {"board": [[1 if outcome == "win" else 0]], "lives": 0 if outcome == "fail" else 3})
	game.get_core_store().committed.disconnect(listener)
	_check(result.ok and state.called and state.reset, mode + " " + outcome + " commits before synchronous successful reset")
	_check(game.get_current_level() == 1 and game.get_core_store().snapshot().product_settlements.is_empty(), "reset durable progress remains authoritative")
	_check(game.get_session_played_count() == 0, "old terminal does not repopulate reset session play count")
	_check(game.get_session_consecutive_wins() == 0 and not game.has_won_since_cold_start(), "old win does not restore reset streak or cold-start qualification")
	_check(game.get_core_store().snapshot().round_services["doku/" + mode].status == "reset", "old result leaves reset round inactive")

func _test_failed_reset_reentered() -> void:
	_check(game.reset_all(), "prepare failed reset replacement")
	game._first_session_runtime = false
	game._start_toast_pct = {7: {"iq": 80.0}}
	game._start_toast_iq_idx = {7: 2}
	var files: RefCounted = game.get_core_store()._file_store
	var state := {"called": false, "reset": false}
	var listener := func(_result: Dictionary) -> void:
		if state.called:
			return
		state.called = true
		files.set_fault_injector_for_tests(Callable())
		state.reset = game.reset_all()
	game.storage_failed.connect(listener)
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var result: bool = game.reset_all()
	files.set_fault_injector_for_tests(Callable())
	game.storage_failed.disconnect(listener)
	_check(not result and state.called and state.reset, "failed reset callback performs a newer successful reset")
	_check(game._first_session_runtime and game._start_toast_pct.is_empty() and game._start_toast_iq_idx.is_empty(), "older failed reset cannot restore caches from before newer reset")

func _test_successful_reset_reentered() -> void:
	_check(game.reset_all(), "prepare nested successful reset")
	game._session_played_count = 9
	var state := {"called": false, "resets": 0, "nested": false}
	var after_reset := func() -> void:
		state.resets += 1
		# 已发布清档后消费者开始新的会话工作，旧请求收尾不得再次清掉它。
		game._session_played_count = 2
	var on_commit := func(_revision: int) -> void:
		if state.called:
			return
		state.called = true
		state.nested = game.reset_all()
	game.all_data_reset.connect(after_reset)
	game.get_core_store().committed.connect(on_commit)
	var result: bool = game.reset_all()
	game.get_core_store().committed.disconnect(on_commit)
	game.all_data_reset.disconnect(after_reset)
	_check(result and state.called and state.nested, "outer and nested reset both complete their durable writes")
	_check(state.resets == 1 and game.get_session_played_count() == 2, "superseded reset neither republishes reset nor clears work after newer reset")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
