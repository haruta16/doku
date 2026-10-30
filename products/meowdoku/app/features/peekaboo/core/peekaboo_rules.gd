## 躲猫猫活动的纯规则：是否当天已领、能否出现、奖励数量与软保护时间。
## 输入来自管理器，返回判断结果；这里不读写存档，也不播放广告。

class_name PeekabooRules
extends RefCounted

const GROUP_OFF: int = 0
const GROUP_FISH_1: int = 1
const GROUP_AD_POPUP: int = 2

const PROP_COUNT: int = 5

const SOFT_PROTECT_SEC: int = 600

const POS_COUNT: int = 5

const APPEAR_RATE_CLAIMED: float = 0.5

const FISH_BASE: int = 1

const FISH_AD: int = 3


## 把今日早于或等于已领日期都视为已领；本地时间回拨不会自动恢复领取资格。
static func is_claimed_today(claimed_date: String, today: String) -> bool:
	if claimed_date.is_empty():
		return false
	return today <= claimed_date


## 先检查解锁和实验开关；今日未领时必出现，已领时按概率保留无奖励交互。
static func should_appear(
	group: int, claimed_today: bool, rng: RandomNumberGenerator, rank_unlocked: bool = true
) -> bool:
	if not rank_unlocked:
		return false
	if group == GROUP_OFF:
		return false
	if not claimed_today:
		return true
	return rng.randf() < APPEAR_RATE_CLAIMED


## 只有符合活动阶段且非离线模式才发收集奖励；猫咪出现不保证一定能领取。
static func grants_reward(rank_state: int, offline_mode: bool = false) -> bool:
	if offline_mode:
		return false
	return (
		rank_state == RankActivityData.State.OPEN_JOINED
		or rank_state == RankActivityData.State.SETTLING
	)


static func is_soft_protected(rank_state: int, remaining_sec: int) -> bool:
	if (
		rank_state != RankActivityData.State.OPEN_JOINED
		and rank_state != RankActivityData.State.OPEN_NOT_JOINED
	):
		return false
	return remaining_sec < SOFT_PROTECT_SEC


static func fish_count(group: int, watched_ad: bool) -> int:
	if group == GROUP_OFF:
		return 0
	if group == GROUP_AD_POPUP and watched_ad:
		return FISH_AD
	return FISH_BASE
