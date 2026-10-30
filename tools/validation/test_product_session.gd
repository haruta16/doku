## RefCounted 产品状态端口运行真实会话；独立 runner 不复制 GameState、页面或 Autoload。
extends SceneTree

const Result = preload("res://scripts/framework/operation_result.gd")
const Session = preload("res://products/meowdoku/gameplay/application/meowdoku_round_session.gd")
const Settlement = preload("res://products/meowdoku/gameplay/application/meowdoku_round_settlement.gd")
const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const Definition = preload("res://products/meowdoku/gameplay/domain/doku_level_definition.gd")
const POLICY := {"retry_once": false, "tool_revive": true, "any_action": false, "next_is_skip": false}
const TODAY := "2026-10-27"

class MemoryProductState extends RefCounted:
	signal committed(revision: int)

	var value: Dictionary
	var fail_next: bool = false
	var _revision: int = 0

	func _init(initial: Dictionary) -> void:
		value = initial.duplicate(true)

	func is_storage_ready() -> bool:
		return true

	func is_open() -> bool:
		return true

	func get_core_store() -> RefCounted:
		return self

	func revision() -> int:
		return _revision

	func get_core_candidate() -> Dictionary:
		return value.duplicate(true)

	func commit_core_candidate(candidate: Dictionary, expected: int) -> Dictionary:
		if fail_next:
			fail_next = false
			return Result.failure("test_write_failed")
		if expected != _revision:
			return Result.failure("revision_conflict")
		var error: String = ProductStore.validate_state(candidate)
		if not error.is_empty():
			return Result.failure("invalid_candidate", error)
		value = candidate.duplicate(true)
		_revision += 1
		committed.emit(_revision)
		return Result.success()

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state := MemoryProductState.new(_fixture())
	var context := _context()
	var checkpoint := {"level": 21, "level_definition": context.content.level_definition.duplicate(true)}
	_check(Definition.validate(checkpoint.level_definition), "frozen media definition validates without a scene registry")
	var bad: Dictionary = checkpoint.level_definition.duplicate(true)
	bad.media["ui/home/logo"] = "season/logo"
	_check(not Definition.validate(bad), "pure definition still rejects non-board media slots")
	var session := Session.new(state, "main")
	var started: Dictionary = session.ensure_started(context, "", checkpoint)
	_check(started.ok, "actual product session starts on a RefCounted state port")
	if not started.ok:
		_finish()
		return
	var before := state.get_core_candidate()
	state.fail_next = true
	var rejected: Dictionary = session.execute("request_hint", {}, {}, checkpoint, {"hint_cost": 1})
	_check(not rejected.ok and rejected.error == "commit_failed" and state.value == before, "failed paid action publishes neither debit, receipt nor product checkpoint")
	var paid: Dictionary = session.execute("request_hint", {}, {}, checkpoint, {"hint_cost": 1})
	_check(paid.ok and state.value.inventory.hint == 0, "same session retries successfully without skipping request sequence")
	if not paid.ok:
		_finish()
		return
	_check(state.value.round_runtime.dda_tool_or_revive_used and state.value.endgame.snapshot.business_round_id == started.round_id, "product flags and checkpoint share the paid commit")
	var resumed := Session.new(state, "main")
	var restored: Dictionary = resumed.ensure_started(context, started.round_id, state.value.endgame.snapshot)
	_check(restored.ok and restored.round_id == started.round_id, "a fresh session restores the same business round without a page")
	before = state.get_core_candidate()
	var reopened: Dictionary = resumed.execute("request_hint", {}, {}, state.value.endgame.snapshot, {"hint_cost": 1})
	_check(not reopened.ok and reopened.error == "insufficient_items" and state.value == before, "restoring a round does not make a new hint request free at zero balance")
	var funded: Dictionary = state.get_core_candidate()
	funded.inventory.hint = 1
	_check(state.commit_core_candidate(funded, state.revision()).ok, "fund a second hint purchase")
	before = state.get_core_candidate()
	state.fail_next = true
	reopened = resumed.execute("request_hint", {}, {}, state.value.endgame.snapshot, {"hint_cost": 1})
	_check(not reopened.ok and reopened.error == "commit_failed" and state.value == before, "failed second purchase keeps the old hint and all product state")
	reopened = resumed.execute("request_hint", {}, {}, state.value.endgame.snapshot, {"hint_cost": 1})
	_check(reopened.ok and reopened.sequence == paid.sequence + 1 and reopened.result.hint_token != paid.result.hint_token and state.value.inventory.hint == 0, "second purchase charges once using the next sequence after retries")
	before = state.get_core_candidate()
	var stale: Dictionary = resumed.execute("apply_hint", {"hint_token": paid.result.hint_token}, {}, state.value.endgame.snapshot)
	_check(not stale.ok and stale.error == "unknown_hint" and state.value == before, "second purchase supersedes the old token without allowing stale effects")
	var applied: Dictionary = resumed.execute("apply_hint", {"hint_token": reopened.result.hint_token}, {}, state.value.endgame.snapshot)
	_check(applied.ok and not applied.changes.is_empty() and state.value.inventory.hint == 0, "hint applies to domain state without presentation or another debit")
	_check(state.value.endgame.snapshot.step_history.size() == 1, "business action atomically mirrors resumable undo history")
	var request := Settlement.main_round(started.round_id + "/attempt#0", 21, "win", {"board": _completed(context.solution)})
	var candidate := state.get_core_candidate()
	var economy := Economy.new(state)
	var won: Dictionary = request.stage(candidate, economy, TODAY, request.saved_dda_policy(candidate))
	_check(won.ok and candidate.profile.current_level == 22 and candidate.inventory.hint == 2, "pure settlement uses frozen reward despite absent content and scene services")
	_check(state.value.profile.current_level == 21 and state.value.inventory.hint == 0, "staged settlement remains unpublished until caller commits")
	_check(state.commit_core_candidate(candidate, state.revision()).ok, "product validates and accepts combined progression and reward")
	var settled := state.get_core_candidate()
	var repeated: Dictionary = request.stage(candidate, economy, TODAY, POLICY)
	_check(repeated.ok and repeated.duplicate and candidate == settled, "settlement retry cannot duplicate frozen reward")
	_check(not resumed.execute("request_hint", {}, {}).ok, "settled session rejects delayed gameplay actions")
	_test_reentrant_receipts(false)
	_test_reentrant_receipts(true)
	_finish()


## 提交通知先取得重复回执，再完成另一合法动作；最外层响应最后才返回。
## 同一宿主的历史收据仍可返回给原调用者，但不能倒退会话的下一请求序号。
func _test_reentrant_receipts(exhausted: bool) -> void:
	var state := MemoryProductState.new(_fixture())
	var context := _context()
	var session := Session.new(state, "main")
	var started: Dictionary = session.ensure_started(context)
	_check(started.ok, "reentrant receipt fixture starts a real round")
	if not started.ok:
		return
	var first_sequence: int = 1
	if exhausted:
		# 用合法的已存记录靠近上界，不通过调用私有 _accept 伪造会话状态。
		var candidate: Dictionary = state.get_core_candidate()
		candidate.round_services["doku/main"].last_sequence = 9223372036854775805
		candidate.round_services["doku/main"].last_receipt = {"kind": "sync", "payload": {}, "result": {}, "changes": []}
		_check(state.commit_core_candidate(candidate, state.revision()).ok, "valid saved record can reach the sequence boundary")
		session = Session.new(state, "main")
		var restored: Dictionary = session.ensure_started(context, started.round_id)
		_check(restored.ok, "fresh session restores the near-exhausted sequence")
		first_sequence = 9223372036854775806
	var delivered := {"done": false}
	var nested := {}
	var on_commit := func(_revision: int) -> void:
		if delivered.done:
			return
		delivered.done = true
		nested["duplicate"] = session.execute("sync", {}, {})
		nested["new_action"] = session.execute("set_mark", {"row": 0, "col": 0, "marked": true}, {})
	state.committed.connect(on_commit)
	var outer: Dictionary = session.execute("sync", {}, {})
	state.committed.disconnect(on_commit)
	_check(delivered.done and nested.duplicate.get("duplicate", false), "reentrant first call observes the already committed receipt")
	_check(nested.new_action.get("ok", false) and nested.new_action.get("sequence") == first_sequence + 1, "later nested action commits once with the next sequence")
	_check(outer.ok and outer.sequence == first_sequence and outer.round_id == started.round_id, "outer result retains its own round and receipt identity")
	var record: Dictionary = state.value.round_services["doku/main"]
	_check(record.last_sequence == first_sequence + 1 and record.snapshot.board[0][0] == 2, "nested board change and latest receipt remain authoritative")
	if exhausted:
		_check(session._next_sequence == -1, "old response cannot replace the exhausted sentinel with a positive sequence")
		var before: Dictionary = state.get_core_candidate()
		var rejected: Dictionary = session.execute("set_mark", {"row": 1, "col": 0, "marked": true}, {})
		_check(not rejected.ok and rejected.error == "stale_sequence" and state.value == before, "exhausted session rejects a following action without changing state")
	else:
		_check(session._next_sequence == 3, "old response cannot rewind the accepted next sequence")
		var before: Dictionary = state.get_core_candidate()
		state.fail_next = true
		var rejected: Dictionary = session.execute("set_mark", {"row": 1, "col": 0, "marked": true}, {})
		_check(not rejected.ok and rejected.error == "commit_failed" and state.value == before, "following action reaches storage and a failed write remains unpublished")
		var following: Dictionary = session.execute("set_mark", {"row": 1, "col": 0, "marked": true}, {})
		_check(following.ok and following.sequence == 3 and state.value.round_services["doku/main"].snapshot.board[1][0] == 2, "following action retries the current sequence without collision or gap")


func _fixture() -> Dictionary:
	var cfg := ConfigFile.new()
	var profile := {"current_level": 21, "current_strategy": 3, "tool_hint": 1, "consecutive_clean_wins": 0, "consecutive_fails": 0, "consecutive_retry_levels": 0, "retry_tracking_strategy": 0, "today_date": TODAY}
	for key: String in profile:
		cfg.set_value("progress", key, profile[key])
	var value := ProductStore.from_legacy(cfg, null, {})
	value["round_runtime"] = {"current_level_dirty": false, "current_level_retried": false, "demoted_this_level": false, "dda_tool_or_revive_used": false, "dda_revive_used": false, "dda_pending_demote": false, "is_daily_first_easy_level": false, "rnr_mod1_exempt": false, "rnr_g_prev_was_max": false}
	return value


func _context() -> Dictionary:
	return {
		"board": [[0, 1, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
		"regions": [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]],
		"solution": [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]],
		"content": {"level": 21, "gameplay_policy": {"dda": POLICY}, "level_definition": {
			"puzzle": {"bank": "doku/levels/bankdata4x4", "rank": 1, "index": 1},
			"reward": {"hint": 2}, "media": {"game/mark": "season/mark"},
		}},
	}


func _completed(solution: Array) -> Array:
	var board: Array = []
	for row: Array in solution:
		var cells: Array = []
		for answer: bool in row:
			cells.append(1 if answer else 0)
		board.append(cells)
	return board


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + message)


func _finish() -> void:
	print("PRODUCT SESSION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
