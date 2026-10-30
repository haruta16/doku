## 产品适配层：把可独立执行的 Doku 用例接入现有 GameState 和残局格式。
## 页面只传值；事务端口不持有页面、棋盘节点或 UI 回调。
class_name MeowdokuRoundSession
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Module = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

## 产品状态端口须提供 is_storage_ready/get_core_store/get_core_candidate/commit_core_candidate。
## 现有 GameState 与无场景的 RefCounted 适配器均可接入；这里不需要 Node 生命周期。
class ProductPort extends RefCounted:
	var state: Object
	var checkpoint: Dictionary = {}
	var key: String

	func _init(product_state: Object, mode: String) -> void:
		state = product_state
		key = "doku/" + mode

	func is_open() -> bool:
		return state.is_storage_ready()

	func revision() -> int:
		return state.get_core_store().revision()

	func snapshot() -> Dictionary:
		return state.get_core_candidate()

	func commit(candidate: Dictionary, expected: int) -> Dictionary:
		var record: Dictionary = candidate.get("round_services", {}).get(key, {})
		var receipt: Dictionary = record.get("last_receipt", {})
		# 沿用原 set_tool_count 的消费副作用，与库存/回执一起落盘；免费用量不结束首次引导。
		if receipt.get("kind") in ["request_hint", "locate", "undo"] and int(receipt.get("result", {}).get("cost", 0)) > 0:
			candidate.profile["has_used_tool"] = true
		if receipt.get("kind") == "life_plus":
			var first_done: bool = bool(receipt.get("result", {}).get("first_done", false))
			if first_done == bool(candidate.profile.get("life_plus_first_done", false)):
				return Result.failure("life_plus_eligibility_changed")
			if first_done:
				candidate.profile["life_plus_first_done"] = true
		if receipt.get("kind") == "revive" and receipt.get("result", {}).get("consume_free_once", false):
			if candidate.profile.get("has_used_revive_free", false):
				return Result.failure("free_revive_unavailable")
			candidate.profile["has_used_revive_free"] = true
		if key == "doku/main" and record.get("last_receipt", {}).get("kind") in ["request_hint", "locate", "revive"]:
			var runtime: Dictionary = candidate.get("round_runtime", {})
			runtime["current_level_dirty"] = true
			runtime["dda_tool_or_revive_used"] = true
			if record.get("last_receipt", {}).get("kind") == "revive":
				runtime["dda_revive_used"] = true
			candidate["round_runtime"] = runtime
		if not checkpoint.is_empty():
			candidate.endgame["snapshot"] = MeowdokuRoundSession.mirror_checkpoint(checkpoint, record)
		return state.commit_core_candidate(candidate, expected)

var _port: ProductPort
var _host: RefCounted
var _mode: String
var _round_id: String = ""
var _next_sequence: int = 1
var _start_sequence: int = 0


func _init(product_state: Object, mode: String) -> void:
	_mode = mode
	_port = ProductPort.new(product_state, mode)
	_host = Host.new(_port)
	_host.register_module("doku", Module.new())


func round_id() -> String:
	return _round_id


## 恢复只接受快照携带的局号和同一题面；同题重开仍然是新局。
func ensure_started(context: Dictionary, restored_id: String = "", checkpoint: Dictionary = {}) -> Dictionary:
	context = context.duplicate(true)
	var content: Dictionary = context.get("content", {})
	if checkpoint.has("level_definition"):
		content["level_definition"] = checkpoint.level_definition.duplicate(true)
	if checkpoint.has("gameplay_policy_snapshot"):
		content["gameplay_policy"] = checkpoint.gameplay_policy_snapshot.duplicate(true)
	context["content"] = content
	if checkpoint.has("life_plus_used"):
		context["life_plus_used"] = bool(checkpoint.life_plus_used)
	if not _round_id.is_empty():
		var current: Dictionary = _host.resume("doku", _mode)
		if not current.get("ok", false):
			return current
		if current.get("round_id") != _round_id or current.get("status") != "active":
			return Result.failure("stale_round")
		return current
	_port.checkpoint = checkpoint.duplicate(true)
	var previous: Dictionary = _host.resume("doku", _mode)
	if previous.get("ok", false) and not restored_id.is_empty() and previous.get("round_id") == restored_id and previous.get("status") == "active":
		var saved: Dictionary = previous.snapshot
		if saved.regions != context.get("regions") or saved.solution != context.get("solution"):
			return Result.failure("restored_puzzle_mismatch")
		_accept(previous)
		return previous
	if not previous.get("ok", false) and previous.get("error") != "missing":
		return previous
	if _start_sequence == 0:
		_start_sequence = int(previous.get("start_sequence", 0)) + 1
	var result: Dictionary = _host.start("doku", _mode, _start_sequence, context)
	if result.get("ok", false):
		_accept(result)
	return result


func execute(kind: String, payload: Dictionary, runtime: Dictionary, checkpoint: Dictionary = {}, policy: Dictionary = {}) -> Dictionary:
	if _round_id.is_empty():
		return Result.failure("round_not_started")
	_port.checkpoint = checkpoint.duplicate(true)
	var result: Dictionary = _host.action("doku", _mode, _round_id, _next_sequence, kind, payload, runtime, policy)
	if result.get("ok", false):
		_accept(result)
		if result.get("duplicate", false):
			result["restore_only"] = true
	return result


func _accept(result: Dictionary) -> void:
	var accepted_round: String = str(result.round_id)
	var next_sequence: int = int(result.next_sequence)
	# 会话固定属于一局；提交的同步通知可能已接受更晚的回执。
	# 外层旧调用仍返回自己的结果，但不能倒退游标，-1 耗尽标记也不能被复活。
	if not _round_id.is_empty():
		if accepted_round != _round_id:
			return
		if _next_sequence == -1 or (next_sequence != -1 and next_sequence < _next_sequence):
			return
	_round_id = accepted_round
	_next_sequence = next_sequence


## 同一次写盘保存提示结果和旧残局，避免扣费成功但棋盘/撤销记录仍在上一状态。
static func mirror_checkpoint(checkpoint: Dictionary, record: Dictionary) -> Dictionary:
	var result: Dictionary = checkpoint.duplicate(true)
	if record.is_empty():
		return result
	result["business_round_id"] = str(record.round_id)
	var snapshot: Dictionary = record.snapshot
	result["lives"] = snapshot.lives
	result["life_plus_used"] = bool(snapshot.get("life_plus_used", result.get("life_plus_used", false)))
	result["business_attempt_sequence"] = int(snapshot.get("attempt_sequence", 0))
	for field: String in ["placed_cats", "marks", "errors", "locked_marks"]:
		result[field] = []
	var board: Array = snapshot.board
	for row in board.size():
		for col in board[row].size():
			var field: String = ""
			match int(board[row][col]):
				States.CAT: field = "placed_cats"
				States.MARK: field = "marks"
				States.ERROR: field = "errors"
				States.LOCKED_MARK: field = "locked_marks"
			if not field.is_empty():
				result[field].append([row, col])
	var receipt: Dictionary = record.get("last_receipt", {})
	if receipt.get("kind") == "revive":
		result["revive_count"] = int(result.get("revive_count", 0)) + 1
	if receipt.get("kind") in ["apply_hint", "locate"]:
		result["step_history"] = snapshot.get("history", []).duplicate(true)
	if receipt.get("kind") == "undo" and receipt.get("result", {}).has("history"):
		result["step_history"] = receipt.result.history.duplicate(true)
		result["highlight_cursor"] = int(receipt.result.get("highlight_cursor", -1))
	return result
