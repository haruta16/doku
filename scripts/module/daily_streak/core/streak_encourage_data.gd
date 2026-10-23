## 打卡鼓励文案选择器：把本地时刻映射到时段标签或实验百分比文案。
class_name StreakEncourageData
extends RefCounted

const SLOT_DAWN: int = 1
const SLOT_MORNING: int = 2
const SLOT_MIDMORNING: int = 3
const SLOT_NOON: int = 4
const SLOT_LAZY: int = 5
const SLOT_DUSK: int = 6
const SLOT_NIGHT: int = 7
const SLOT_MIDNIGHT: int = 8

const KEY_PREFIX_NAME: String = "DAILY_STREAK_TAG_"
const KEY_PREFIX_TAG: String = "DAILY_STREAK_ENCOURAGE_"

const SLOT_SUFFIX: Array[String] = [
	"DAWN",
	"MORNING",
	"MIDMORNING",
	"NOON",
	"LAZY",
	"DUSK",
	"NIGHT",
	"MIDNIGHT",
]

const _COARSE: Array = [
	[300, 480, SLOT_DAWN],
	[480, 600, SLOT_MORNING],
	[600, 720, SLOT_MIDMORNING],
	[720, 840, SLOT_NOON],
	[840, 1080, SLOT_LAZY],
	[1080, 1320, SLOT_DUSK],
	[1320, 1440, SLOT_NIGHT],
	[0, 300, SLOT_MIDNIGHT],
]

const _TOP: Array = [
	[300, 330, "DAILY_STREAK_EARLY_TOP_1"],
	[330, 360, "DAILY_STREAK_EARLY_TOP_3"],
	[360, 420, "DAILY_STREAK_EARLY_TOP_5"],
	[420, 480, "DAILY_STREAK_EARLY_TOP_10"],
	[480, 600, "DAILY_STREAK_EARLY_TOP_20"],
	[600, 720, "DAILY_STREAK_EARLY_TOP_30"],
	[1320, 1440, "DAILY_STREAK_LATE_STILL_8"],
	[0, 300, "DAILY_STREAK_LATE_STILL_10"],
]


## 把小时分钟映射到半开时段区间；百分比实验没有匹配文案时返回隐藏状态。
static func resolve(hour: int, minute: int, uses_top_percent: bool) -> Dictionary:
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		push_error("StreakEncourageData: 时间越界 hour=%d minute=%d,回落对照组" % [hour, minute])
		return {"visible": false, "slot": 0, "name_key": "", "body_key": ""}
	var m: int = hour * 60 + minute
	var slot: int = _slot_of(m)
	if slot == 0:
		return {"visible": false, "slot": 0, "name_key": "", "body_key": ""}
	var body_key: String = ""
	if uses_top_percent:
		for row: Array in _TOP:
			if m >= int(row[0]) and m < int(row[1]):
				body_key = String(row[2])
				break
		if body_key.is_empty():
			return {"visible": false, "slot": 0, "name_key": "", "body_key": ""}
	else:
		body_key = KEY_PREFIX_TAG + SLOT_SUFFIX[slot - 1]
	return {
		"visible": true,
		"slot": slot,
		"name_key": KEY_PREFIX_NAME + SLOT_SUFFIX[slot - 1],
		"body_key": body_key,
	}


static func resolve_now(uses_top_percent: bool) -> Dictionary:
	var d: Dictionary = Time.get_datetime_dict_from_system(false)
	return resolve(int(d["hour"]), int(d["minute"]), uses_top_percent)


static func _slot_of(minute_of_day: int) -> int:
	for row: Array in _COARSE:
		if minute_of_day >= int(row[0]) and minute_of_day < int(row[1]):
			return int(row[2])
	return 0
