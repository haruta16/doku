## 躲猫猫状态管理器；冷启动时依据实验、日期和活动解锁条件决定出现位置，并保存到 peekaboo.cfg。
## 奖励表现由 PeekabooFlow 执行；领取日期与交互状态在这里统一更新。

extends Node

const SAVE_PATH := "user://peekaboo.cfg"
const _SECTION := "peekaboo"

var _data: PeekabooData = PeekabooData.new()

var _session_evaluated: bool = false

var _soft_protected: bool = false
var _feature_saving: bool = false
var _pending_claim_retry: Dictionary = {}
var _retry_after_msec: int = 0


func _init() -> void:
	print("[BootProbe] autoloads_instanced=%dms" % Time.get_ticks_msec())


func _ready() -> void:
	GameState.feature_state_changed.connect(_on_feature_state_changed)
	_load()

	GameState.all_data_reset.connect(_reset)
	_log(
		(
			"init: claimed_date=%s cat_present=%s prop=%d pos=%d interacted=%s"
			% [
				"(never)" if _data.claimed_date.is_empty() else _data.claimed_date,
				_data.cat_present,
				_data.prop_index,
				_data.pos_index,
				_data.interacted
			]
		)
	)


## 每次冷启动只评估一次出现条件；选中道具和位置后写入活动状态，页面切换不会重新抽签。
func evaluate_on_cold_start() -> void:
	var group: int = int(ABTestManager.peekaboo_cat.peek_value())
	if _session_evaluated:
		return
	_session_evaluated = true
	var claimed_today: bool = _is_claimed_today()
	var rng: RandomNumberGenerator = _rng()

	var rank_unlocked: bool = GameState.get_current_level() >= RankActivityConfig.UNLOCK_LEVEL
	var appear: bool = PeekabooRules.should_appear(group, claimed_today, rng, rank_unlocked)
	_data.cat_present = appear
	_data.interacted = false
	if appear:
		_data.prop_index = rng.randi_range(0, PeekabooRules.PROP_COUNT - 1)
		_data.pos_index = rng.randi_range(0, PeekabooRules.POS_COUNT - 1)
	if not _save():
		return
	_log(
		(
			"evaluate: group=%d claimed_today=%s rank_unlocked=%s(lv=%d/阈%d) → present=%s prop=%d pos=%d"
			% [
				group,
				claimed_today,
				rank_unlocked,
				GameState.get_current_level(),
				RankActivityConfig.UNLOCK_LEVEL,
				appear,
				_data.prop_index,
				_data.pos_index
			]
		)
	)


func get_cat_state() -> Dictionary:
	return {
		"present": _data.cat_present and not _data.interacted and not _soft_protected,
		"prop_index": _data.prop_index,
		"pos_index": _data.pos_index,
		"claimed_today": _is_claimed_today(),
	}


## 保存已领取日期并标记已交互；日期只向前推进，避免本地日期倒退造成重复领取。
func mark_claimed(now_unix: int) -> void:
	var date: String = _local_date_str(now_unix)
	if date > _data.claimed_date:
		_data.claimed_date = date
	_data.interacted = true
	if not _save():
		return
	_log("mark_claimed: claimed_date=%s（当日额度已消耗，本次入账日期=%s）" % [_data.claimed_date, date])


func mark_interacted() -> void:
	_data.interacted = true
	if not _save():
		return
	_log("mark_interacted: 猫已互动（纯互动，当日额度未消耗）")


## 记录本会话的软保护状态，避免活动快到期时继续进入会被结算打断的交互。
func mark_soft_protected() -> void:
	if _soft_protected:
		return
	_soft_protected = true
	_log("mark_soft_protected: 活动快结束（剩余 < %ds）→ 本世不再出猫" % PeekabooRules.SOFT_PROTECT_SEC)


func _is_claimed_today() -> bool:
	return PeekabooRules.is_claimed_today(_data.claimed_date, _today_str())


func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


func _local_date_str(unix: int) -> String:
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var dt: Dictionary = Time.get_date_dict_from_unix_time(unix + bias_sec)
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


func _reset() -> void:
	_pending_claim_retry.clear()
	_data = PeekabooData.new()
	_session_evaluated = false

	_soft_protected = false
	if not _save():
		return
	_log("reset：清档（all_data_reset）→ 无猫、当日额度归零")


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func _save() -> bool:
	_feature_saving = true
	var prior: Dictionary = GameState.get_feature_state("peekaboo")
	var data: Dictionary = _data.to_dict()
	if prior.has("last_claim"):
		data["last_claim"] = prior.last_claim
	var result: Dictionary = GameState.commit_feature_state("peekaboo", data)
	_feature_saving = false
	if not result.ok:
		_load()
	return result.ok


func _load() -> void:
	_data = PeekabooData.from_dict(GameState.get_feature_state("peekaboo"))


func _log(msg: String) -> void:
	print("[Peekaboo] " + msg)

func _on_feature_state_changed(id: String, data: Dictionary) -> void:
	if id == "peekaboo" and not _feature_saving:
		_data = PeekabooData.from_dict(data)


func get_event_id() -> String:
	var rank: Dictionary = GameState.get_feature_state("rank_activity")
	return "%d/%d/%d/%s" % [GameState.get_storage_epoch(), DataSyncManager.get_account_epoch(), int(rank.get("period_count", 0)), str(rank.get("robot_key", ""))]


func get_claim_day() -> String:
	return _today_str()


## 日期、账号世代、排行周期与领取回执在同一事务验证，迟到广告不能挪到另一日/另一周期。
func claim_reward(amount: int, expected_day: String, expected_event_id: String) -> Dictionary:
	var candidate: Dictionary = GameState.get_core_candidate()
	var revision: int = GameState.get_core_store().revision()
	var data: Dictionary = candidate.features.get("peekaboo", {}).duplicate(true)
	var last: Dictionary = data.get("last_claim", {})
	if last.get("day", "") == expected_day and last.get("event_id", "") == expected_event_id:
		var duplicate: Dictionary = last.get("result", {}).duplicate(true)
		duplicate["ok"] = true
		duplicate["duplicate"] = true
		return duplicate
	if expected_day != _today_str() or expected_event_id != get_event_id() or amount <= 0 or str(data.get("claimed_date", "")) >= expected_day:
		return {"ok": false, "error": "stale_peekaboo_claim"}
	var result: Dictionary = RankActivityManager.stage_external_collect(candidate, amount)
	if not result.ok:
		return result
	data["claimed_date"] = expected_day
	data["interacted"] = true
	data["last_claim"] = {"day": expected_day, "event_id": expected_event_id, "result": result.duplicate(true)}
	candidate.features["peekaboo"] = data
	var committed: Dictionary = GameState.commit_core_candidate(candidate, revision)
	if not committed.ok:
		_pending_claim_retry = {"amount": amount, "day": expected_day, "event_id": expected_event_id}
		_retry_after_msec = Time.get_ticks_msec() + 5000
		return committed
	_pending_claim_retry.clear()
	RankActivityManager.ranking_changed.emit()
	result["duplicate"] = false
	return result

func _process(_delta: float) -> void:
	if _pending_claim_retry.is_empty() or Time.get_ticks_msec() < _retry_after_msec:
		return
	var pending: Dictionary = _pending_claim_retry.duplicate(true)
	if str(pending.day) != get_claim_day() or str(pending.event_id) != get_event_id():
		_pending_claim_retry.clear()
		return
	claim_reward(int(pending.amount), str(pending.day), str(pending.event_id))
