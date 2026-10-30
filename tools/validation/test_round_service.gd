## 通过 tools/run_validation.py 执行；使用隔离 user:// 下的真实双槽存档验证崩溃恢复边界。
extends SceneTree

var _checks: int = 0

const Result = preload("res://scripts/framework/operation_result.gd")

const Files = preload("res://scripts/framework/storage/save_store.gd")
const CoreStore = preload("res://scripts/framework/storage/local_core_store.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Doku = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const Block = preload("res://scripts/examples/block/domain/block_probe_module.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

var _failures: int = 0
var _directory: String
var _files: Files
var _store: CoreStore
var _host: Host


func _initialize() -> void:
	_directory = "user://round_service_validation_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_directory)
	_open_store()
	_test_doku_hint_and_recovery()
	_test_block_and_namespace()
	var before_restart: Dictionary = _store.snapshot()
	_open_store()
	_check(_store.snapshot() == before_restart, "restart restores both module namespaces and inventory")
	if _failures == 0:
		print("PASS: RoundService Doku hints, durable retries, failed writes, settlement and Block reuse checks=%d failures=0" % _checks)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + message)


func _open_store() -> void:
	_files = Files.new("round-test-only", _directory, true, _directory + "/a.save", _directory + "/b.save", _directory + "/flag")
	_store = CoreStore.new(_files, 1)
	var opened: Dictionary = _store.open({"inventory": {"hint": 5, "locate": 0, "undo": 0}, "round_services": {}})
	_check(opened.get("ok", false), "core store opens")
	_host = Host.new(_store)
	_check(_host.register_module("doku", Doku.new()), "Doku registers without UI")
	_check(_host.register_module("block_probe", Block.new()), "Block registers in same unchanged host")


func _doku_context() -> Dictionary:
	var solution: Array = []
	var board: Array = []
	var regions: Array = []
	var answer_columns: Array[int] = [1, 3, 0, 2]
	for row in range(4):
		var answers: Array = []
		var cells: Array = []
		var areas: Array = []
		for col in range(4):
			answers.append(col == answer_columns[row])
			cells.append(States.CAT if row == 0 and col == 1 else States.EMPTY)
			areas.append(row)
		solution.append(answers)
		board.append(cells)
		regions.append(areas)
	return {"board": board, "regions": regions, "solution": solution, "lives": 3, "reward": {"hint": 2}}


func _test_doku_hint_and_recovery() -> void:
	var context: Dictionary = _doku_context()
	var started: Dictionary = _host.start("doku", "main", 1, context)
	_check(started.get("ok", false), "Doku starts")
	if not started.get("ok", false):
		return
	var round_id: String = started.round_id
	_check(_host.start("doku", "main", 1, context).get("duplicate", false), "start retry returns same round")
	var altered: Dictionary = context.duplicate(true)
	altered["hint_cost"] = 0
	_check(_host.start("doku", "main", 1, altered).get("error") == "sequence_collision", "same start sequence cannot change context")
	var before_request: Dictionary = _store.snapshot()
	_files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed_request: Dictionary = _host.action("doku", "main", round_id, 1, "request_hint")
	_check(failed_request.get("error") == "commit_failed" and _store.snapshot() == before_request, "failed paid request publishes neither debit nor hint receipt")
	var cause: Dictionary = failed_request.get("cause", {})
	_check(Result.code(cause) == "write_failed" and not Result.detail(failed_request).is_empty(), "host retains the underlying write error and diagnostic detail")
	var diagnostic: String = Result.describe(failed_request)
	_check(diagnostic.contains("commit_failed") and diagnostic.contains("write_failed") and diagnostic.contains(Result.detail(cause)), "caller diagnostics show both the failed use case and its underlying cause")
	cause["detail"] = "caller changed its own result"
	_check(_files.last_result().detail != cause.detail, "wrapped failure does not expose the storage diagnostic dictionary")
	_files.set_fault_injector_for_tests(Callable())
	var requested: Dictionary = _host.action("doku", "main", round_id, 1, "request_hint")
	_check(requested.get("ok", false), "paid hint request succeeds")
	if not requested.get("ok", false):
		return
	var token: String = requested.result.hint_token
	_check(_store.snapshot().inventory.hint == 4, "displaying hint consumes one item")
	requested.result.hint["cell"] = Vector2i(99, 99)
	_check(_host.resume("doku", "main").snapshot.pending_hint.hint.cell != Vector2i(99, 99), "UI enrichment cannot mutate saved hint")
	var duplicate: Dictionary = _host.action("doku", "main", round_id, 1, "request_hint")
	_check(duplicate.get("duplicate", false) and _store.snapshot().inventory.hint == 4, "same request never charges twice")
	before_request = _store.snapshot()
	_files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed_reopen: Dictionary = _host.action("doku", "main", round_id, 2, "request_hint")
	_check(failed_reopen.get("error") == "commit_failed" and _store.snapshot() == before_request, "failed new hint purchase preserves balance and previous token")
	_files.set_fault_injector_for_tests(Callable())
	var viewed_again: Dictionary = _host.action("doku", "main", round_id, 2, "request_hint")
	_check(viewed_again.get("ok", false) and viewed_again.result.cost == 1 and _store.snapshot().inventory.hint == 3, "new hint request charges again even while the board is unchanged")
	_check(viewed_again.result.hint_token != token, "new purchase replaces the previous hint credential")
	var old_token: String = token
	token = viewed_again.result.hint_token
	duplicate = _host.action("doku", "main", round_id, 2, "request_hint")
	_check(duplicate.get("duplicate", false) and duplicate.result.hint_token == token and _store.snapshot().inventory.hint == 3, "retrying the same purchase sequence still does not charge twice")
	before_request = _store.snapshot()
	var old_apply: Dictionary = _host.action("doku", "main", round_id, 3, "apply_hint", {"hint_token": old_token})
	_check(old_apply.get("error") == "unknown_hint" and _store.snapshot() == before_request, "replaced hint token cannot apply or advance the request sequence")
	_open_store()
	var restored: Dictionary = _host.resume("doku", "main")
	_check(restored.snapshot.pending_hint.token == token, "paid hint survives restart")
	var applied: Dictionary = _host.action("doku", "main", round_id, 3, "apply_hint", {"hint_token": token})
	_check(applied.get("ok", false) and not applied.changes.is_empty(), "restored hint applies headlessly")
	_check(_store.snapshot().inventory.hint == 3, "apply does not charge again")
	var repeated: Dictionary = _host.action("doku", "main", round_id, 4, "apply_hint", {"hint_token": token})
	_check(repeated.get("ok", false) and repeated.changes.is_empty(), "new sequence cannot apply same hint twice")
	_check(_host.action("doku", "main", round_id, 3, "apply_hint", {"hint_token": token}).get("error") == "stale_sequence", "old request beyond last receipt is rejected without effect")
	started = _host.start("doku", "main", 2, context)
	var next_id: String = started.round_id
	_check(_host.action("doku", "main", round_id, 5, "request_hint").get("error") == "stale_round", "old callbacks cannot target replacement round")
	requested = _host.action("doku", "main", next_id, 1, "request_hint")
	token = requested.result.hint_token
	var runtime: Dictionary = {"board": context.board.duplicate(true), "lives": 3}
	runtime.board[3][3] = States.MARK
	var before: Dictionary = _store.snapshot()
	var stale: Dictionary = _host.action("doku", "main", next_id, 2, "apply_hint", {"hint_token": token}, runtime)
	_check(stale.get("error") == "stale_hint" and _store.snapshot() == before, "old hint cannot apply after legacy board changes")
	requested = _host.action("doku", "main", next_id, 2, "request_hint", {}, runtime, {"hint_cost": 0})
	_check(requested.get("ok", false) and requested.result.cost == 0 and _store.snapshot().inventory.hint == 2, "product price policy supports free hint without UI counts")
	token = requested.result.hint_token
	before = _store.snapshot()
	_files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed: Dictionary = _host.action("doku", "main", next_id, 3, "apply_hint", {"hint_token": token})
	_check(failed.get("error") == "commit_failed" and _store.snapshot() == before, "failed commit publishes neither board nor receipt")
	_files.set_fault_injector_for_tests(Callable())
	applied = _host.action("doku", "main", next_id, 3, "apply_hint", {"hint_token": token})
	_check(applied.get("ok", false), "same sequence is retryable after failed commit")
	var won_board: Array = context.board.duplicate(true)
	for row in range(4):
		for col in range(4):
			won_board[row][col] = States.CAT if bool(context.solution[row][col]) else States.EMPTY
	var settled: Dictionary = _host.settle("doku", "main", next_id, 4, {}, {"board": won_board, "lives": 3})
	_check(settled.get("ok", false) and settled.result.outcome == "won", "Doku outcome verified by module")
	_check(_store.snapshot().inventory.hint == 4, "winning reward commits with terminal state")
	_check(_host.settle("doku", "main", next_id, 5).get("duplicate", false) and _store.snapshot().inventory.hint == 4, "settlement repeats cannot duplicate reward")


func _test_block_and_namespace() -> void:
	var doku_before: Dictionary = _host.resume("doku", "main")
	var started: Dictionary = _host.start("block_probe", "main", 1, {
		"size": 3, "board": [[1, 1, 0], [1, 0, 0], [0, 0, 0]],
		"pieces": [[[0, 0]], [[0, 0]]], "reward": {"hint": 1},
	})
	_check(started.get("ok", false), "Block starts in shared host")
	if not started.get("ok", false):
		return
	var round_id: String = started.round_id
	var revision: int = _store.revision()
	_check(_host.action("block_probe", "main", round_id, 1, "place", {"row": 0, "col": 0}).get("error") == "invalid_placement", "occupied placement rejected")
	_check(_store.revision() == revision, "rejected move does not advance persistent state")
	var placed: Dictionary = _host.action("block_probe", "main", round_id, 1, "place", {"row": 0, "col": 2})
	_check(placed.get("ok", false) and placed.result.score == 11, "valid block placement clears row and adds score")
	_check(placed.snapshot.occupied[0] == [0, 0, 0], "row cleared in stored model")
	_check(placed.changes.size() == 2 and placed.changes[1].kind == "clear_lines", "host carries module-specific multi-step result")
	_check(_host.action("block_probe", "main", round_id, 1, "place", {"row": 0, "col": 2}).get("duplicate", false), "block retry is idempotent")
	_check(_host.action("block_probe", "main", round_id, 2, "place", {"row": 99, "col": 0}).get("error") == "invalid_placement", "out of bounds placement rejected")
	placed = _host.action("block_probe", "main", round_id, 2, "place", {"row": 1, "col": 1})
	_check(placed.get("ok", false) and placed.result.finished and placed.result.score == 12, "finite block queue ends the game")
	var balance: int = _store.snapshot().inventory.hint
	var settled: Dictionary = _host.settle("block_probe", "main", round_id, 3)
	_check(settled.get("ok", false) and _store.snapshot().inventory.hint == balance + 1, "Block shares common inventory and settlement")
	_check(_host.settle("block_probe", "main", round_id, 4).get("duplicate", false) and _store.snapshot().inventory.hint == balance + 1, "Block reward is not duplicated")
	_check(_host.resume("doku", "main").snapshot == doku_before.snapshot, "Block never changes Doku namespace")
	_check(_host.start("doku", "../main", 1, _doku_context()).get("error") == "invalid_namespace", "namespace cannot alias another module")
