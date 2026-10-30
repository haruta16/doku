## 一次产品结算：检查尝试身份，把进度、DDA、奖励和回执写入同一候选。
## 不读写文件、不访问页面或 Autoload；调用者负责提交，失败时丢弃候选。
class_name MeowdokuRoundSettlement
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const Rules = preload("res://products/meowdoku/gameplay/application/meowdoku_settlement_rules.gd")
const Definition = preload("res://products/meowdoku/gameplay/domain/doku_level_definition.gd")
const DokuModule = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")

var round_id: String
var mode: String
var level: int = 0
var date: String = ""
var outcome: String
var elapsed_sec: int = 0
var beat_percent: float = 0.0
var legacy_completed: bool = false
var runtime_snapshot: Dictionary = {}
var retry_params: Dictionary = {}
var context: Dictionary = {}
var progress_stager: Callable = Callable()


static func main_round(id: String, level_number: int, result: String, runtime: Dictionary = {}, retry: Dictionary = {}) -> MeowdokuRoundSettlement:
	var request := MeowdokuRoundSettlement.new()
	request.round_id = id
	request.mode = "main"
	request.level = level_number
	request.outcome = result
	request.runtime_snapshot = runtime.duplicate(true)
	request.retry_params = retry.duplicate(true)
	return request


static func daily_round(id: String, day: String, result: String, elapsed: int, beat: float, runtime: Dictionary = {}) -> MeowdokuRoundSettlement:
	var request := MeowdokuRoundSettlement.new()
	request.round_id = id
	request.mode = "daily"
	request.date = day
	request.outcome = result
	request.elapsed_sec = elapsed
	request.beat_percent = beat
	request.runtime_snapshot = runtime.duplicate(true)
	return request


static func preview_round(id: String, result: String, runtime: Dictionary = {}) -> MeowdokuRoundSettlement:
	var request := MeowdokuRoundSettlement.new()
	request.round_id = id
	request.mode = "preview"
	request.outcome = result
	request.runtime_snapshot = runtime.duplicate(true)
	return request


static func legacy_main(level_number: int) -> MeowdokuRoundSettlement:
	var request := main_round("legacy-main/" + str(level_number), level_number, "win")
	request.legacy_completed = true
	return request


## 开局时保存的策略优先；旧档没有完整策略时，由调用者提供当前产品策略。
func saved_dda_policy(candidate: Dictionary) -> Dictionary:
	if legacy_completed or mode != "main" or level <= 0:
		return {}
	var policy: Variant = candidate.get("round_services", {}).get("doku/main", {}).get("snapshot", {}).get("content", {}).get("gameplay_policy", {}).get("dda", {})
	if not policy is Dictionary:
		return {}
	for field: String in ["retry_once", "tool_revive", "any_action", "next_is_skip"]:
		if typeof(policy.get(field)) != TYPE_BOOL:
			return {}
	return policy.duplicate(true)


## candidate 来自已校验的产品存档；主线需提供完整 DDA 策略，其余模式传空字典。
func stage(candidate: Dictionary, economy: RefCounted, today: String, dda_policy: Dictionary) -> Dictionary:
	if legacy_completed and (candidate.is_empty() or level <= 0):
		return _failure("invalid_legacy_completion")
	if round_id.is_empty() or mode not in ["main", "daily", "preview"] or outcome not in ["win", "fail", "quit"] or level < 0:
		return _failure("invalid_settlement")
	if mode == "daily" and (date.is_empty() or elapsed_sec < 0 or not is_finite(beat_percent)):
		return _failure("invalid_settlement")
	if candidate.is_empty():
		return _failure("not_open")
	var receipt := {"mode": mode, "level": level, "date": date, "outcome": outcome}
	var slot := "legacy_main" if legacy_completed else mode
	var settlements: Dictionary = candidate.get("product_settlements", {})
	var previous: Dictionary = settlements.get(slot, {})
	var identity := _stage_legacy(candidate, previous) if legacy_completed else _stage_round(candidate, previous, receipt)
	if not identity.ok or identity.get("duplicate", false):
		return identity
	# 迟到的请求不能改变另一关的 DDA 或每日成绩。
	if mode == "main" and level > 0 and int(candidate.profile.get("current_level", 1)) != level:
		return _failure("stale_level")
	if mode == "daily" and not str(candidate.profile.get("daily_started_date", "")).is_empty() and candidate.profile.daily_started_date != date:
		return _failure("stale_daily")
	var progress: Dictionary = _stage_progress(candidate, today, dda_policy)
	if not progress.get("ok", false):
		return progress
	var reward := _stage_reward(candidate, economy)
	if not reward.ok:
		return reward
	# 每模式只留当前局最后一次尝试；RoundService 的单调局号拒绝更早的请求。
	settlements[slot] = {"round_id": identity.parent_id, "last_attempt": identity.attempt, "receipt": receipt, "level": level}
	candidate["product_settlements"] = settlements
	return Result.success({"duplicate": false, "grants": reward.grants})


func _stage_round(candidate: Dictionary, previous: Dictionary, receipt: Dictionary) -> Dictionary:
	var separator := round_id.rfind("/attempt#")
	if separator < 0:
		return _failure("invalid_attempt")
	var parent_id := round_id.substr(0, separator)
	var suffix := round_id.substr(separator + 9)
	if not suffix.is_valid_int() or suffix.to_int() < 0 or str(suffix.to_int()) != suffix:
		return _failure("invalid_attempt")
	var attempt := suffix.to_int()
	var active: Dictionary = candidate.round_services.get("doku/" + mode, {})
	if active.get("round_id", "") != parent_id or active.get("status", "") == "reset":
		return _failure("stale_round")
	var content: Dictionary = active.get("snapshot", {}).get("content", {})
	if mode == "main" and content.has("level") and int(content.level) != level:
		return _failure("round_level_mismatch")
	if previous.get("round_id", "") == parent_id:
		var last_attempt := int(previous.get("last_attempt", -1))
		if attempt == last_attempt:
			if previous.get("receipt", {}) == receipt:
				return Result.success({"status": "already_settled", "duplicate": true})
			return _failure("settlement_conflict")
		if attempt < last_attempt:
			return _failure("stale_attempt")
		if attempt != last_attempt + 1:
			return _failure("attempt_gap")
	elif attempt != 0:
		return _failure("attempt_gap")
	if active.get("status", "") != "active":
		return _failure("stale_round")
	if int(active.get("snapshot", {}).get("attempt_sequence", 0)) != attempt:
		return _failure("attempt_not_active")
	var module := DokuModule.new()
	var snapshot_error: String = module.validate_snapshot(active.get("snapshot", {}))
	if not snapshot_error.is_empty():
		return _failure("invalid_round_snapshot", snapshot_error)
	var synced: Dictionary = module.sync_runtime(active.get("snapshot", {}), runtime_snapshot)
	if not synced.get("ok", false):
		return synced
	if outcome == "win":
		var terminal: Dictionary = module.settle_snapshot(synced.snapshot, {})
		if not terminal.get("ok", false) or terminal.get("result", {}).get("outcome") != "won":
			return _failure("round_not_won")
	active["snapshot"] = synced.snapshot
	if outcome == "fail":
		active.snapshot["lives"] = 0
		active.snapshot["finished_attempt"] = attempt
	else:
		active["status"] = "settled"
		active["settlement"] = {"outcome": outcome, "attempt_sequence": attempt}
	candidate.round_services["doku/" + mode] = active
	return Result.success({"parent_id": parent_id, "attempt": attempt})


## 旧完整残局没有宿主局号；只允许验证后的当前关快照兼容收尾一次。
func _stage_legacy(candidate: Dictionary, previous: Dictionary) -> Dictionary:
	if int(previous.get("level", 0)) == level:
		return Result.success({"status": "already_settled", "duplicate": true})
	var snapshot: Dictionary = candidate.endgame.snapshot
	if not str(snapshot.get("business_round_id", "")).is_empty() or int(snapshot.get("level", 0)) != level:
		return _failure("invalid_legacy_completion")
	var size := int(snapshot.get("size", 0))
	var solution: Variant = snapshot.get("solution", [])
	var cats: Variant = snapshot.get("placed_cats", [])
	if size <= 0 or not solution is Array or not cats is Array or solution.size() != size or cats.size() != size:
		return _failure("invalid_legacy_completion")
	for row in size:
		if typeof(solution[row]) != TYPE_INT or int(solution[row]) < 0 or int(solution[row]) >= size or not cats.has([row, int(solution[row])]):
			return _failure("invalid_legacy_completion")
	return Result.success({"parent_id": round_id, "attempt": 0})


func _stage_progress(candidate: Dictionary, today: String, dda_policy: Dictionary) -> Dictionary:
	if mode == "main" and progress_stager.is_valid() and not legacy_completed:
		var staged: Variant = progress_stager.call(candidate, level, outcome, context.duplicate(true))
		if not staged is Dictionary or typeof(staged.get("ok")) != TYPE_BOOL:
			return _failure("invalid_progress_result")
		if not staged.ok:
			return staged
		if outcome == "fail" and not retry_params.is_empty():
			candidate.profile["retry_puzzle_level"] = level
			candidate.profile["retry_puzzle_params"] = retry_params.duplicate(true)
		candidate.endgame["snapshot"] = {}
		context["committed_effects"] = staged.get("effects", []).duplicate(true)
		return Result.success()
	if not legacy_completed:
		Rules.finish_game(candidate.profile, today)
	if mode == "main":
		if level > 0:
			if outcome == "win":
				Rules.main_win(candidate.profile, candidate.round_runtime, level, dda_policy)
			else:
				Rules.main_fail(candidate.profile, candidate.round_runtime, level, dda_policy)
		if outcome == "fail" and not retry_params.is_empty():
			candidate.profile["retry_puzzle_level"] = level
			candidate.profile["retry_puzzle_params"] = retry_params.duplicate(true)
		candidate.endgame["snapshot"] = {}
	elif mode == "daily" and outcome == "win":
		candidate.endgame["daily_snapshot"] = {}
		Rules.daily_win(candidate.profile, date, elapsed_sec, beat_percent)
	return Result.success()


func _stage_reward(candidate: Dictionary, economy: RefCounted) -> Dictionary:
	if mode != "main" or outcome != "win" or legacy_completed:
		return Result.success({"grants": []})
	# 奖励跟随开局内容冻结；结算不重新读取远端关卡表。
	var definition: Dictionary = candidate.round_services.get("doku/main", {}).get("snapshot", {}).get("content", {}).get("level_definition", {})
	if not definition.is_empty() and not Definition.validate(definition):
		return _failure("invalid_saved_level_definition")
	var items: Array = []
	for kind: String in definition.get("reward", {}):
		items.append({"kind": kind, "count": int(definition.reward[kind])})
	if items.is_empty():
		return Result.success({"grants": []})
	var registered: Dictionary = economy.stage_award(candidate, items, 0, "level_win")
	if not registered.get("ok", false):
		return registered
	return economy.stage_claim(candidate, int(registered.uid))


## 保留旧调用者的 status 字段；新调用者统一按 error 判断失败原因。
static func _failure(code: String, detail: String = "") -> Dictionary:
	return Result.failure(code, detail, {"status": code})
