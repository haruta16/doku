## 打卡存档模型：序列化连签和历史信息，并提供本地与云端进度的合并规则。
class_name StreakData
extends RefCounted

const StreakHistory: GDScript = preload("res://scripts/module/daily_streak/core/streak_history.gd")

## 第 7 天宝箱的奖励基数（道具 kind → 个数），StreakManager 据此生成奖励
const REWARD_BASE: Dictionary = {"hint": 2, "locate": 2}

const BEST_STREAK_CAP: int = 36500

# ---- 存档字段（字段名就是 streak.cfg 里的 key） ----
var current_streak: int = 0 # 当前连续打卡天数
var best_streak: int = 0 # 历史最长连续天数
var last_checkin_date: String = "" # 最近一次打卡日期 yyyy-mm-dd，空串 = 从没打过

var last_checkin_minute: int = -1

var streak_start_weekday: int = -1 # 本轮第 1 天是星期几（0 = 周日），-1 = 本轮还没开始

var reward_cycle_day: int = 0 # 奖励周期里的第几天（1~7 循环），0 = 还没开始

var history_ranges: Array = []

var last_group: int = -1 # 上次记录的 AB 分组；-1 = 还没记录过（控制组也记 -1）

var pending_switch_page: int = 0 # 待弹出的切组说明页编号（1/2/3），0 = 不用弹

var pending_win_checkin_date: String = ""

var icon_group: int = -1
var icon_group_date: String = ""


func to_dict() -> Dictionary:
	return {
		"current_streak": current_streak,
		"best_streak": best_streak,
		"last_checkin_date": last_checkin_date,
		"last_checkin_minute": last_checkin_minute,
		"streak_start_weekday": streak_start_weekday,
		"reward_cycle_day": reward_cycle_day,
		"history_ranges": history_ranges.duplicate(true),
		"last_group": last_group,
		"pending_switch_page": pending_switch_page,
		"pending_win_checkin_date": pending_win_checkin_date,
		"icon_group": icon_group,
		"icon_group_date": icon_group_date,
	}


## 恢复存档字段并规范化历史区间，当前有效连签对应日期在裁剪时受到保护。
static func from_dict(source: Dictionary) -> StreakData:
	var data: StreakData = StreakData.new()
	data.current_streak = source.get("current_streak", 0)
	data.best_streak = source.get("best_streak", 0)
	data.last_checkin_date = source.get("last_checkin_date", "")

	data.last_checkin_minute = source.get("last_checkin_minute", -1)
	data.streak_start_weekday = source.get("streak_start_weekday", -1)
	data.reward_cycle_day = source.get("reward_cycle_day", 0)
	data.last_group = source.get("last_group", -1)
	data.pending_switch_page = source.get("pending_switch_page", 0)
	data.pending_win_checkin_date = source.get("pending_win_checkin_date", "")
	data.icon_group = source.get("icon_group", -1)
	data.icon_group_date = source.get("icon_group_date", "")
	var last_jdn: int = history_date_to_jdn(data.last_checkin_date)
	var covers_valid_dates: bool = (
		data.current_streak > 0
		and last_jdn >= StreakHistory.MIN_JDN
		and data.current_streak <= last_jdn - StreakHistory.MIN_JDN + 1
	)
	var protected_jdn: int = last_jdn if covers_valid_dates else StreakHistory.INVALID_JDN
	data.history_ranges = StreakHistory.normalize_ranges(
		source.get("history_ranges", []), protected_jdn
	)
	return data


## 严格检查年月日文本和数字字符，再交给公历日期校验，非法日期返回无效日序。
static func history_date_to_jdn(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if (
		parts.size() != 3
		or parts[0].length() < 1
		or parts[0].length() > 4
		or parts[1].length() != 2
		or parts[2].length() != 2
	):
		return StreakHistory.INVALID_JDN
	for part: String in parts:
		for index in part.length():
			var codepoint: int = part.unicode_at(index)
			if codepoint < 48 or codepoint > 57:
				return StreakHistory.INVALID_JDN
	return StreakHistory.date_to_jdn(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())


## 取两端较大的连签与周期计数，日期和分钟采用较新一端，再推导周起点。
static func resolve_merge(
	local: Dictionary, cloud: Dictionary, local_jdn: int, cloud_jdn: int
) -> Dictionary:
	var best: int = maxi(int(local.get("best_streak", 0)), int(cloud.get("best_streak", 0)))

	var cur: int = maxi(
		0, maxi(int(local.get("current_streak", 0)), int(cloud.get("current_streak", 0)))
	)

	var local_cycle: int = int(local.get("reward_cycle_day", local.get("current_streak", 0)))
	var cloud_cycle: int = int(cloud.get("reward_cycle_day", cloud.get("current_streak", 0)))
	var cycle: int = maxi(0, maxi(local_cycle, cloud_cycle))

	var use_cloud: bool = cloud_jdn > local_jdn
	var src: Dictionary = cloud if use_cloud else local
	var src_weekday: int = int(src.get("streak_start_weekday", -1))
	if src_weekday < -1 or src_weekday > 6:
		src_weekday = -1
	var src_jdn: int = cloud_jdn if use_cloud else local_jdn
	var start_weekday: int = derive_start_weekday(src_jdn, cycle, src_weekday)

	var minute: int = int(src.get("last_checkin_minute", -1))
	if minute < 0 or minute > 1439:
		minute = -1
	return {
		"current_streak": cur,
		"best_streak": clampi(maxi(best, cur), 0, BEST_STREAK_CAP),
		"last_checkin_date": str(src.get("last_checkin_date", "")),
		"last_checkin_minute": minute,
		"streak_start_weekday": start_weekday,
		"reward_cycle_day": cycle,
	}


static func derive_start_weekday(last_jdn: int, cycle: int, fallback_weekday: int) -> int:
	if last_jdn <= 0 or cycle <= 0:
		return fallback_weekday
	return posmod((last_jdn + 1) % 7 - (cycle - 1) % 7, 7)
