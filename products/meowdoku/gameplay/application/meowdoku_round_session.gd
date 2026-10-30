## 产品适配层：把可独立执行的 Doku 用例接入现有 GameState 和残局格式。
## 页面只传值；事务端口不持有页面、棋盘节点或 UI 回调。
class_name MeowdokuRoundSession
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Module = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const ActionFacts = preload("res://products/meowdoku/gameplay/application/meowdoku_action_facts.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

## 产品状态端口须提供 is_storage_ready/get_core_store/get_core_candidate/commit_core_candidate。
## 非空选题计划另需 stage_round_selection(candidate, plan, checkpoint)，由产品装配内容版本与策略。
## 现有 GameState 与无场景的 RefCounted 适配器均可接入；这里不需要 Node 生命周期。
class ProductPort extends RefCounted:
	var state: Object
	var checkpoint: Dictionary = {}
	var selection_plan: Dictionary = {}
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
		var committed_plan: Dictionary = selection_plan.duplicate(true)
		var selected_duplicate: bool = false
		if not committed_plan.is_empty():
			if not state.has_method("stage_round_selection"):
				return Result.failure("selection_adapter_unavailable")
			var selected: Dictionary = state.stage_round_selection(candidate, committed_plan, checkpoint)
			if not selected.get("ok", false):
				return selected
			selected_duplicate = bool(selected.get("duplicate", false))
		var record: Dictionary = candidate.get("round_services", {}).get(key, {})
		var receipt: Dictionary = record.get("last_receipt", {})
		var kind: String = str(receipt.get("kind", ""))
		var snapshot: Dictionary = record.get("snapshot", {})
		var round_kind: int = int(snapshot.get("kind", 1))
		var frozen: Dictionary = snapshot.get("content", {}).get("selection_policy", {})
		var isolated: bool = round_kind in [2, 3] and int(frozen.get("normal_level", 0)) in [11808, 11809]
		if kind in ["request_hint", "locate", "mouse", "activate_draft", "undo"]:
			if kind in ["request_hint", "locate", "undo"] and int(receipt.get("result", {}).get("cost", 0)) > 0:
				candidate.profile["has_used_tool"] = true
			var activity: Dictionary = ActionFacts.stage_activity(candidate, "tool", key.trim_prefix("doku/"), frozen)
			if not activity.get("ok", false):
				return activity
		if kind == "revive":
			var activity: Dictionary = ActionFacts.stage_activity(candidate, "revive", key.trim_prefix("doku/"), frozen)
			if not activity.get("ok", false):
				return activity
			var mode: String = key.trim_prefix("doku/")
			var stats: Dictionary = candidate.endgame.get("stats", {})
			var total: Dictionary = stats.get(mode + "_total", {})
			total["rv_count"] = int(total.get("rv_count", 0)) + 1
			total["revive_count"] = int(total.get("revive_count", 0)) + 1
			stats[mode + "_total"] = total
			candidate.endgame["stats"] = stats
			if key == "doku/main":
				# 原 notify_level_revived 的唯一事实：清除待失败标志，与复活同提交。
				var rank_activity: Dictionary = candidate.get("features", {}).get("rank_activity", {})
				if not rank_activity.is_empty():
					rank_activity["level_failed_pending"] = false
				if not isolated:
					candidate.profile["pre_cat_revived_this_level"] = true
				if round_kind == 3:
					var precat: Dictionary = candidate.profile.get("golden_fish_pre_cat_session", {})
					if not precat.is_empty():
						precat["revived"] = true
						candidate.profile["golden_fish_pre_cat_session"] = precat
		if kind in ["place_cat", "draft_commit"]:
			var facts: Dictionary = ActionFacts.stage_action_facts(candidate, key.trim_prefix("doku/"), receipt, snapshot)
			if not facts.get("ok", false):
				return facts
		var performance_delta: Dictionary = receipt.get("result", {}).get("performance_delta", {})
		if not performance_delta.is_empty() and key != "doku/preview":
			var mode: String = key.trim_prefix("doku/")
			var stats: Dictionary = candidate.endgame.get("stats", {})
			var round_stats: Dictionary = stats.get(mode + "_round", {})
			var total_stats: Dictionary = stats.get(mode + "_total", {})
			var step: int = int(performance_delta.get("step_used", 0))
			round_stats["step_used"] = int(round_stats.get("step_used", 0)) + step
			total_stats["step_total"] = int(total_stats.get("step_total", 0)) + step
			for stat: String in performance_delta.get("tool_used", {}):
				var count: int = int(performance_delta.tool_used[stat])
				if stat != "draft_used":
					round_stats[stat] = int(round_stats.get(stat, 0)) + count
				if stat != "hint_apply_used":
					total_stats[stat + "_total"] = int(total_stats.get(stat + "_total", 0)) + count
			for stat: String in performance_delta.get("total_stats", {}):
				total_stats[stat] = int(total_stats.get(stat, 0)) + int(performance_delta.total_stats[stat])
			stats[mode + "_round"] = round_stats
			stats[mode + "_total"] = total_stats
			candidate.endgame["stats"] = stats
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
		if key == "doku/main" and not isolated and kind in ["request_hint", "locate", "mouse", "activate_draft", "revive"]:
			var runtime: Dictionary = candidate.get("round_runtime", {})
			runtime["current_level_dirty"] = true
			if round_kind == 1:
				runtime["dda_tool_or_revive_used"] = true
				if kind == "revive":
					runtime["dda_revive_used"] = true
			candidate["round_runtime"] = runtime
		if not checkpoint.is_empty():
			if key != "doku/preview":
				candidate.endgame["daily_snapshot" if key == "doku/daily" else "snapshot"] = MeowdokuRoundSession.mirror_checkpoint(checkpoint, record)
		var effect_guard: Dictionary = {}
		if not committed_plan.is_empty() and state.has_method("capture_selection_effect_context"):
			effect_guard = state.capture_selection_effect_context()
		var committed: Dictionary = state.commit_core_candidate(candidate, expected)
		if committed.get("ok", false) and not selected_duplicate and not committed_plan.is_empty() and state.has_method("publish_selection_effects"):
			state.publish_selection_effects(committed_plan, effect_guard)
		return committed

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
func ensure_started(context: Dictionary, restored_id: String = "", checkpoint: Dictionary = {}, selection_plan: Dictionary = {}) -> Dictionary:
	_port.selection_plan = selection_plan.duplicate(true)
	context = context.duplicate(true)
	var content: Dictionary = context.get("content", {})
	if not selection_plan.is_empty():
		content["selection_policy"] = selection_plan.get("selection_policy", {}).duplicate(true)
	elif checkpoint.get("selection_policy") is Dictionary:
		content["selection_policy"] = checkpoint.selection_policy.duplicate(true)
	if checkpoint.has("level_definition"):
		content["level_definition"] = checkpoint.level_definition.duplicate(true)
	if checkpoint.has("gameplay_policy_snapshot"):
		content["gameplay_policy"] = checkpoint.gameplay_policy_snapshot.duplicate(true)
	context["content"] = content
	if not context.has("performance"):
		var performance: Dictionary = checkpoint.get("performance", {}).duplicate(true)
		if performance.is_empty():
			performance = {"score": int(checkpoint.get("score", 0)), "combo": int(checkpoint.get("combo", 0)), "max_combo": int(checkpoint.get("max_combo", checkpoint.get("combo", 0)))}
			performance["se_count"] = int(checkpoint.get("se_count", 0))
			performance["se_last_step"] = int(checkpoint.get("se_last_step", -1))
		context["performance"] = performance
	if checkpoint.has("life_plus_used"):
		context["life_plus_used"] = bool(checkpoint.life_plus_used)
	if not _round_id.is_empty():
		var current: Dictionary = _host.resume("doku", _mode)
		if not current.get("ok", false):
			return current
		if current.get("round_id") != _round_id or current.get("status") != "active":
			return Result.failure("stale_round")
		_port.selection_plan = {}
		return current
	_port.checkpoint = checkpoint.duplicate(true)
	var previous: Dictionary = _host.resume("doku", _mode)
	if previous.get("ok", false) and not restored_id.is_empty() and previous.get("round_id") == restored_id and previous.get("status") == "active":
		var saved: Dictionary = previous.snapshot
		if saved.regions != context.get("regions") or saved.solution != context.get("solution"):
			return Result.failure("restored_puzzle_mismatch")
		var resumed: Dictionary = previous
		if not selection_plan.is_empty():
			resumed = _host.action("doku", _mode, str(previous.round_id), int(previous.next_sequence), "sync", {}, {}, {})
		if resumed.get("ok", false):
			_accept(resumed)
			_port.selection_plan = {}
		return resumed
	if not previous.get("ok", false) and previous.get("error") != "missing":
		return previous
	if _start_sequence == 0:
		_start_sequence = int(previous.get("start_sequence", 0)) + 1
	var result: Dictionary = _host.start("doku", _mode, _start_sequence, context)
	if result.get("ok", false):
		_accept(result)
		_port.selection_plan = {}
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
	if snapshot.get("performance") is Dictionary:
		var performance: Dictionary = snapshot.performance
		result["performance"] = performance.duplicate(true)
		for score_field: String in ["score", "combo", "max_combo"]:
			result[score_field] = int(performance[score_field])
		result["se_count"] = int(performance.se_count)
		result["se_last_step"] = int(performance.se_last_step)
	result["lives"] = snapshot.lives
	result["life_cap"] = snapshot.get("life_cap", 3)
	result["lives_inf"] = snapshot.get("lives_inf", false)
	result["draft_active"] = snapshot.get("draft_active", false)
	result["selection_policy"] = snapshot.get("content", {}).get("selection_policy", {}).duplicate(true)
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
	if receipt.get("kind") in ["apply_hint", "locate", "mouse", "draft_commit", "draft_clear"]:
		result["step_history"] = snapshot.get("history", []).duplicate(true)
	if receipt.get("kind") == "undo" and receipt.get("result", {}).has("history"):
		result["step_history"] = receipt.result.history.duplicate(true)
		result["highlight_cursor"] = int(receipt.result.get("highlight_cursor", -1))
	return result
