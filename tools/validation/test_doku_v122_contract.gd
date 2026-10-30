extends SceneTree

const Module = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const Actions = preload("res://products/meowdoku/gameplay/domain/doku_action_rules.gd")
const Board = preload("res://products/meowdoku/gameplay/domain/doku_board_state.gd")
const Hints = preload("res://products/meowdoku/gameplay/domain/doku_hint_service.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

class MemoryStore extends RefCounted:
	var data: Dictionary = {"inventory": {"mouse": 2, "draft": 2, "hint": 2}, "round_services": {}}
	var rev: int = 0
	var fail: bool = false
	func is_open() -> bool: return true
	func revision() -> int: return rev
	func snapshot() -> Dictionary: return data.duplicate(true)
	func commit(candidate: Dictionary, expected: int) -> Dictionary:
		if fail or expected != rev:
			return {"ok": false, "error": "injected_write_failure"}
		data = candidate.duplicate(true)
		rev += 1
		return {"ok": true}

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_mouse_transaction()
	_test_draft_and_lives()
	_test_reverse_hint()
	_test_committed_board_tracking()
	_test_performance_projection()
	_test_draft_statistics_projection()
	print("Doku 1.22 contract checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _context() -> Dictionary:
	var answer: Array = [1, 3, 0, 2]
	var board: Array = []
	var regions: Array = []
	var solution: Array = []
	for row in range(4):
		board.append([0, 0, 0, 0])
		regions.append([row, row, row, row])
		var line: Array = []
		for col in range(4): line.append(col == answer[row])
		solution.append(line)
	return {"board": board, "regions": regions, "solution": solution, "lives": 3}

func _test_mouse_transaction() -> void:
	var store := MemoryStore.new()
	var host := Host.new(store)
	host.register_module("doku", Module.new())
	var started: Dictionary = host.start("doku", "main", 1, _context())
	_check(started.get("ok", false), "ordinary start remains supported")
	if not started.get("ok", false): return
	var before: Dictionary = store.snapshot()
	store.fail = true
	var failed: Dictionary = host.action("doku", "main", started.round_id, 1, "mouse", {"seed": 123}, {}, {"cost": 1})
	_check(not failed.ok and store.snapshot() == before, "failed mouse write changes neither board, history nor inventory")
	store.fail = false
	var used: Dictionary = host.action("doku", "main", started.round_id, 1, "mouse", {"seed": 123}, {}, {"cost": 1})
	_check(used.get("ok", false), "mouse targets commit successfully")
	if not used.get("ok", false): return
	_check(used.result.targets.size() == 3 and used.snapshot.history.size() == 1 and store.data.inventory.mouse == 1, "mouse commits all targets, history and one price")
	_check(used.snapshot.performance.step_used == 1 and used.snapshot.performance.tool_used.mouse_used == 1, "mouse steps and usage are already committed before animation")
	_check(used.snapshot.performance.score == 0 and used.result.performance_events.is_empty(), "three mouse marks do not manufacture a cat score")
	_check(used.result.targets[0].has("before"), "mouse animation receives prior cell state")
	var repeated: Dictionary = host.action("doku", "main", started.round_id, 1, "mouse", {"seed": 123}, {}, {"cost": 1})
	_check(repeated.get("duplicate", false) and store.data.inventory.mouse == 1, "mouse request retry is idempotent")
	var activation: Dictionary = host.action("doku", "main", started.round_id, 2, "activate_draft", {}, {}, {"cost": 1, "enabled": true})
	_check(activation.get("ok", false) and store.data.inventory.draft == 1, "draft charges at entry")
	var cleared: Dictionary = host.action("doku", "main", started.round_id, 3, "draft_clear")
	_check(cleared.get("ok", false) and not cleared.snapshot.draft_active, "leaving draft closes activation")
	var entered: Dictionary = host.action("doku", "main", started.round_id, 4, "activate_draft", {}, {}, {"cost": 1, "enabled": true})
	_check(entered.get("ok", false) and store.data.inventory.draft == 0, "second draft entry charges again")

func _test_draft_and_lives() -> void:
	var context: Dictionary = _context()
	context.board[0][0] = States.DRAFT_CAT
	context.board[1][0] = States.DRAFT_CAT
	context.board[2][0] = States.DRAFT_CAT
	context.board[3][0] = States.DRAFT_CROSS
	var before: Array = context.board.duplicate(true)
	var lethal: Dictionary = Actions.commit_draft(context.board, context.solution, 1)
	_check(lethal.lives == 0 and lethal.get("lethal", false), "draft batch detects lethal errors before placing correct cats")
	_check(lethal.board[2][0] == States.EMPTY and lethal.board[3][0] == States.EMPTY and lethal.wrong_positions.size() == 1, "lethal batch discards correct cats and crosses and only shows remaining-life errors")
	_check(context.board == before, "planning draft never mutates caller board")
	var infinite: Dictionary = Actions.commit_draft(context.board, context.solution, 1, true)
	_check(infinite.lives == 1 and infinite.board[2][0] == States.CAT, "infinite lives commits valid draft cats without losing life")
	var large: Dictionary = _context()
	large.life_cap = 7
	large.lives = 7
	var module := Module.new()
	_check(module.create_snapshot(large).get("ok", false), "life cap greater than three is valid")
	large.lives = 0
	var snapshot: Dictionary = module.create_snapshot(large).snapshot
	var revive: Dictionary = module.apply_action(snapshot, "revive", {}, {"policy": {"revive_lives": 3}})
	_check(revive.get("ok", false) and revive.snapshot.lives == 7, "nonstandard cap is restored exactly")
	_check(not Actions.tap(States.ERROR, false).pending and Actions.tap(States.CAT, false).pending, "1.22 tap error and cat pending semantics stay distinct")

func _test_reverse_hint() -> void:
	var context: Dictionary = _context()
	var hint: Dictionary = {"strategy": "R3b", "regions": [0, 1], "locked_rows": [0], "locked_cols": []}
	var applied: Dictionary = Hints.apply_hint(context.board, context.regions, hint)
	_check(applied.ok and applied.changes.size() == 4, "reverse set lock marks selected regions outside locked rows")
	_check(applied.board[0][0] == States.EMPTY and applied.board[1][0] == States.MARK, "reverse hint uses inverse region exclusion")


func _test_committed_board_tracking() -> void:
	var board := Board.new(4)
	board.transition_cell(0, 0, States.MARK, 100)
	board.transition_cell(0, 0, States.EMPTY, 2000)
	board.set_input_locked(3, 3, true)
	var committed: Array = board.get_board()
	committed[1][3] = States.CAT
	_check(board.apply_committed_board(committed, 3000), "committed board publishes without reset")
	_check(board.has_ever_marked_x(0, 0) and board.is_input_locked(3, 3), "paid action preserves prior clap history and input locks")


func _test_performance_projection() -> void:
	var module := Module.new()
	var opened: Dictionary = module.create_snapshot(_context())
	var first: Dictionary = module.apply_action(opened.snapshot, "place_cat", {"row": 0, "col": 1, "scoring": {"consumed_step": 1}}, {})
	_check(first.snapshot.performance.score == 576 and first.snapshot.performance.combo == 1 and first.snapshot.performance.se_last_step == 1, "first cat freezes score and consumed step using the 1.22 formula")
	var second: Dictionary = module.apply_action(first.snapshot, "place_cat", {"row": 1, "col": 3, "scoring": {"consumed_step": 2}}, {})
	_check(second.snapshot.performance.score == 1248 and second.result.performance_events[0].gain == 672, "second cat adds the next 1.22 combo gain exactly once")
	var wrong: Dictionary = module.apply_action(second.snapshot, "place_cat", {"row": 2, "col": 1}, {})
	_check(wrong.snapshot.performance.combo == 0 and wrong.snapshot.performance.se_count == 0 and wrong.snapshot.performance.score == 1248, "wrong guess breaks combo while preserving committed score")
	var mouse_context: Dictionary = _context()
	for row: int in 4:
		for col: int in 4:
			if not mouse_context.solution[row][col]:
				mouse_context.board[row][col] = States.MARK
	var mouse_start: Dictionary = module.create_snapshot(mouse_context)
	var mouse_cat: Dictionary = module.apply_action(mouse_start.snapshot, "mouse", {"seed": 123}, {"policy": {"cost": 1}})
	_check(mouse_cat.snapshot.performance.score == 576 and mouse_cat.result.performance_events[0].has("row"), "mouse cat score and presentation coordinates commit before animation")
	var stale: Dictionary = {"performance": {"score": -1}}
	_check(not module.sync_runtime(wrong.snapshot, stale).ok, "invalid score synchronization cannot publish a snapshot")
	var rules: Script = load("res://products/meowdoku/gameplay/domain/doku_round_performance.gd")
	_check(rules.tier_bonus(8, 6, 1) == 768 and rules.tier_bonus(10, 12, 10) == 0 and rules.tier_bonus(9, 10, 0) == 0, "frozen tier formulas retain size, group, and first-cat boundary semantics")

func _test_draft_statistics_projection() -> void:
	var module := Module.new()
	var context: Dictionary = _context()
	context.draft_active = true
	context.performance = {"score": 0, "combo": 0, "max_combo": 0, "se_count": 0, "se_last_step": -1, "step_used": 2, "tool_used": {}, "draft_elapsed_ms": 2500}
	context.board[0][1] = States.DRAFT_CAT
	context.board[1][3] = States.DRAFT_CROSS
	var started: Dictionary = module.create_snapshot(context)
	var cleared: Dictionary = module.apply_action(started.snapshot, "draft_clear", {}, {})
	_check(cleared.ok and cleared.result.performance_delta.total_stats.draft_error_total == 1, "draft exit scores wrong crosses from the pre-clear board")
	_check(cleared.result.performance_delta.total_stats.draft_time_total_ms == 2500 and cleared.snapshot.performance.draft_elapsed_ms == 0, "draft duration commits exactly once and resets the activation clock")
	_check(cleared.result.performance_delta.total_stats.draft_stop_used_total == 1 and not cleared.snapshot.draft_active, "draft cancel closes paid activation and commits one stop")
	var repeated: Dictionary = module.apply_action(cleared.snapshot, "draft_clear", {}, {})
	_check(not repeated.ok, "closed draft cannot re-count its exit statistics")
