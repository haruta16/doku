## 陪伴猫纯业务模型：计算活动模式、罐头、糖果、饱食度及奖励账本，不直接操作界面。
extends RefCounted

enum Mode { CONTROL, HALLOWEEN_REWARDS, DAILY_CANS, HALLOWEEN_COSMETIC, SATIETY, DAILY_INTERACT }

enum FeedResult { ACCEPTED, UNAVAILABLE, FULL }

const EVENT_START: int = 1792886400

const EVENT_END: int = 1794096000
const INVENTORY_CAP: int = 999
const WINS_PER_CAN: int = 10
const SATIETY_PER_FEED: float = 40.0
const SATIETY_FULL_THRESHOLD: float = 99.0
const DECAY_PER_SECOND: float = 40.0 / 86400.0
const REWARD_THRESHOLDS: Array[int] = [20, 50, 90, 140, 200]
const REWARD_KINDS: Array[String] = [
	"avatar", "trial_costume", "mouse", "frame", "permanent_costume"
]

const CLOUD_KEYS: Array[String] = ["candy_total"]

const RETIRED_CLOUD_KEYS: Array[String] = [
	"companion_cans",
	"companion_can_progress",
	"companion_has_received_cans",
	"companion_granted",
	"companion_shown",
	"companion_tutorials",
	"companion_wins",
	"companion_event_ended",
	"companion_trial_expires_at",
	"companion_satiety",
	"companion_satiety_at",
	"companion_satiety_enabled",
	"companion_satiety_active",
	"companion_reward_progress",
	"companion_reached_tiers",
	"home_companion_cans",
	"home_companion_candy_total"
]

var _data: Dictionary = {}


## 复制并规范化存档，夹取库存与饱食度范围，修复旧档缺失的账本结构。
func _init(saved: Dictionary = {}) -> void:
	_data = saved.duplicate(true)
	_data["cans"] = clampi(_integer("cans"), 0, INVENTORY_CAP)
	_data["can_progress"] = clampi(_integer("can_progress"), 0, WINS_PER_CAN - 1)
	_data["candy_total"] = maxi(0, _integer("candy_total"))
	_data["satiety"] = clampf(_number("satiety", 60.0), 0.0, 100.0)
	_data["satiety_at"] = maxi(0, _integer("satiety_at"))
	_data["satiety_enabled"] = _boolean("satiety_enabled")
	_data["satiety_active"] = _boolean("satiety_active")
	_data["event_ended"] = _boolean("event_ended")
	_data["trial_expires_at"] = maxi(0, _integer("trial_expires_at"))
	for key: String in ["tutorials", "granted", "shown", "wins"]:
		var ledger: Variant = _data.get(key, {})
		_data[key] = ledger.duplicate(true) if ledger is Dictionary else {}

	var tutorials: Dictionary = _data["tutorials"]
	_data["has_received_cans"] = (
		_boolean("has_received_cans")
		or int(_data["cans"]) > 0
		or tutorials.get(str(Mode.DAILY_CANS), false) == true
		or tutorials.get(str(Mode.SATIETY), false) == true
		or _data["satiety_enabled"]
	)


func snapshot() -> Dictionary:
	return _data.duplicate(true)


func closed_notice_needed(previous: Mode, current: Mode) -> bool:
	if not _data["event_ended"]:
		return false
	var had_companion: bool = (
		previous in [Mode.HALLOWEEN_REWARDS, Mode.DAILY_CANS, Mode.SATIETY, Mode.DAILY_INTERACT]
	)
	var closes_companion: bool = current == Mode.CONTROL or current == Mode.HALLOWEEN_COSMETIC
	return had_companion and closes_companion


static func format_countdown(remaining: int) -> String:
	var seconds: int = maxi(0, remaining)
	if seconds >= 86400:
		return "%sd %02dh" % [seconds / 86400, seconds / 3600 % 24]
	return "%02d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]


## 按活动时间决定实际模式，并记住活动已经结束，避免回拨时间重新打开活动。
func effective_mode(requested: Mode, local_now: int) -> Mode:
	if local_now >= EVENT_END:
		_data["event_ended"] = true
	if requested != Mode.HALLOWEEN_REWARDS and requested != Mode.HALLOWEEN_COSMETIC:
		return requested
	if _data["event_ended"]:
		return Mode.DAILY_INTERACT if requested == Mode.HALLOWEEN_REWARDS else Mode.CONTROL
	if local_now < EVENT_START:
		return Mode.CONTROL
	return requested


func enter_home(
	requested: Mode, local_now: int, event_now: int = -1, decay_scale: float = 1.0
) -> Mode:
	var resolved: Mode = effective_mode(requested, event_now if event_now >= 0 else local_now)
	sync_satiety_mode(resolved, local_now, decay_scale)
	if resolved == Mode.SATIETY and not _data["satiety_enabled"] and int(_data["cans"]) > 0:
		_data["satiety_enabled"] = true
		_data["satiety"] = 60.0
	return resolved


## 按本地秒时间结算饱食衰减，再更新当前模式与计时基准。
func sync_satiety_mode(resolved: Mode, local_now: int, decay_scale: float = 1.0) -> void:
	var entering_satiety: bool = resolved == Mode.SATIETY
	if _data["satiety_active"] and _data["satiety_enabled"]:
		var elapsed: int = maxi(0, local_now - int(_data["satiety_at"]))
		_data["satiety"] = maxf(
			0.0, float(_data["satiety"]) - elapsed * DECAY_PER_SECOND * decay_scale
		)
	_data["satiety_active"] = entering_satiety
	_data["satiety_at"] = local_now


## 用 game_id 去重符合条件的胜利；每 10 局积一罐，活动期胜利另积糖果。
func record_win(
	requested: Mode,
	local_now: int,
	game_id: String,
	eligible: bool,
	event_win_time: int = -1,
	event_now: int = -1
) -> Dictionary:
	if not eligible or game_id.is_empty():
		return {}
	var wins: Dictionary = _data["wins"]
	if wins.has(game_id):
		return {}
	var resolved: Mode = effective_mode(requested, event_now if event_now >= 0 else local_now)
	var produces_cans: bool = resolved == Mode.DAILY_CANS or resolved == Mode.SATIETY
	var produces_candy: bool = resolved == Mode.HALLOWEEN_REWARDS and not all_rewards_granted()

	if produces_candy and (event_win_time < EVENT_START or event_win_time >= EVENT_END):
		produces_candy = false
	if not produces_cans and not produces_candy:
		return {}
	wins[game_id] = true
	var result: Dictionary = {"can_awarded": false, "candy_awarded": false}
	if produces_cans:
		_data["can_progress"] = int(_data["can_progress"]) + 1
		if int(_data["can_progress"]) >= WINS_PER_CAN:
			_data["can_progress"] = 0
			var previous_cans: int = int(_data["cans"])
			_data["cans"] = mini(INVENTORY_CAP, previous_cans + 1)
			result["can_awarded"] = int(_data["cans"]) > previous_cans
			if result["can_awarded"]:
				_data["has_received_cans"] = true
	if produces_candy:
		_data["candy_total"] = int(_data["candy_total"]) + 1
		result["candy_awarded"] = true
	result["pending_grants"] = pending_grants()
	return result


func feed(resolved: Mode) -> bool:
	return feed_result(resolved) == FeedResult.ACCEPTED


## 校验模式、库存与饱食上限，通过后扣一罐并在饱食模式增加 40 点。
func feed_result(resolved: Mode) -> FeedResult:
	if resolved == Mode.HALLOWEEN_REWARDS or resolved == Mode.DAILY_INTERACT:
		return FeedResult.ACCEPTED
	if resolved != Mode.DAILY_CANS and resolved != Mode.SATIETY:
		return FeedResult.UNAVAILABLE
	if int(_data["cans"]) <= 0:
		return FeedResult.UNAVAILABLE
	if (
		resolved == Mode.SATIETY
		and _data["satiety_enabled"]
		and float(_data["satiety"]) >= SATIETY_FULL_THRESHOLD
	):
		return FeedResult.FULL
	_data["cans"] = int(_data["cans"]) - 1
	if resolved == Mode.SATIETY and _data["satiety_enabled"]:
		_data["satiety"] = minf(100.0, float(_data["satiety"]) + SATIETY_PER_FEED)
	return FeedResult.ACCEPTED


func reward_progress() -> Dictionary:
	return progress_for_total(int(_data["candy_total"]))


## 把累计糖果换算成当前奖励档的局部进度，界面不直接按总量填满单档进度条。
static func progress_for_total(total: int) -> Dictionary:
	var previous: int = 0
	for tier: int in REWARD_THRESHOLDS.size():
		var threshold: int = REWARD_THRESHOLDS[tier]
		if total < threshold:
			return {
				"tier": tier,
				"kind": REWARD_KINDS[tier],
				"progress": total - previous,
				"required": threshold - previous
			}
		previous = threshold
	return {
		"tier": REWARD_THRESHOLDS.size() - 1,
		"kind": REWARD_KINDS.back(),
		"progress": 60,
		"required": 60
	}


## 找出已到门槛但未记入发奖账本的档位，供外层执行实际资产发放。
func pending_grants() -> Array[int]:
	var pending: Array[int] = []
	var granted: Dictionary = _data["granted"]
	for tier: int in REWARD_THRESHOLDS.size():
		if (
			int(_data["candy_total"]) >= REWARD_THRESHOLDS[tier]
			and not granted.get(str(tier), false)
		):
			pending.append(tier)
	return pending


## 验证门槛并只标记一次发奖；标记本身不修改道具或装扮资产。
func acknowledge_grant(tier: int) -> bool:
	if (
		tier < 0
		or tier >= REWARD_THRESHOLDS.size()
		or int(_data["candy_total"]) < REWARD_THRESHOLDS[tier]
	):
		return false
	var granted: Dictionary = _data["granted"]
	if granted.get(str(tier), false):
		return false
	granted[str(tier)] = true
	return true


## 筛出已经发奖但尚未演出的档位，把资产到账与界面表现分开记录。
func pending_presentations() -> Array[int]:
	var pending: Array[int] = []
	var granted: Dictionary = _data["granted"]
	var shown: Dictionary = _data["shown"]
	for tier: int in REWARD_THRESHOLDS.size():
		if granted.get(str(tier), false) and not shown.get(str(tier), false):
			pending.append(tier)
	return pending


## 消费待演出记录；首次展示试用装扮时记录 24 小时后过期的本地时间。
func acknowledge_presentation(tier: int, local_now: int) -> bool:
	var pending: Array[int] = pending_presentations()
	if not pending.has(tier):
		return false
	var shown: Dictionary = _data["shown"]
	shown[str(tier)] = true
	if REWARD_KINDS[tier] == "trial_costume" and _integer("trial_expires_at") == 0:
		_data["trial_expires_at"] = local_now + 86400
	return true


func mark_presented(tier: int) -> void:
	var shown: Dictionary = _data["shown"]
	shown[str(tier)] = true


func is_tier_granted(tier: int) -> bool:
	var granted: Dictionary = _data["granted"]
	return granted.get(str(tier), false)


func all_rewards_granted() -> bool:
	var granted: Dictionary = _data["granted"]
	for tier: int in REWARD_THRESHOLDS.size():
		if not granted.get(str(tier), false):
			return false
	return true


func tutorial_needed(resolved: Mode) -> bool:
	if (
		resolved != Mode.HALLOWEEN_REWARDS
		and resolved != Mode.DAILY_CANS
		and resolved != Mode.SATIETY
	):
		return false
	if resolved != Mode.HALLOWEEN_REWARDS and int(_data["cans"]) <= 0:
		return false
	var tutorials: Dictionary = _data["tutorials"]
	return not tutorials.get(str(resolved), false)


func complete_tutorial(resolved: Mode) -> void:
	var tutorials: Dictionary = _data["tutorials"]
	tutorials[str(resolved)] = true


## 只导出明确列入 CLOUD_KEYS 的字段，本版同步糖果累计值。
func export_cloud() -> Dictionary:
	var remote: Dictionary = {}
	for key: String in CLOUD_KEYS:
		var value: Variant = _data[key]
		remote["companion_" + key] = value.duplicate(true) if value is Dictionary else value
	return remote


static func has_cloud_data(remote: Dictionary) -> bool:
	for key: String in CLOUD_KEYS:
		if remote.has("companion_" + key):
			return true
	return remote.has("home_companion_candy_total")


## 读取当前与旧版糖果字段，验证数值后恢复模型，不覆盖其他本地交互账本。
func restore_cloud(remote: Dictionary) -> void:
	for key: String in CLOUD_KEYS:
		var remote_key: String = "companion_" + key
		if not remote.has(remote_key) and key == "candy_total":
			remote_key = "home_companion_" + key
		if not remote.has(remote_key):
			continue
		var value: Variant = remote[remote_key]
		if value is int or value is float:
			_data[key] = maxi(0, int(value))


func _integer(key: String, fallback: int = 0) -> int:
	var value: Variant = _data.get(key, fallback)
	return int(value) if value is int or value is float else fallback


func _number(key: String, fallback: float) -> float:
	var value: Variant = _data.get(key, fallback)
	return float(value) if value is int or value is float else fallback


func _boolean(key: String) -> bool:
	var value: Variant = _data.get(key, false)
	return value if value is bool else false
