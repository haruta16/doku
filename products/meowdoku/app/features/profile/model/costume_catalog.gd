## 服装目录与轮换规则；统一有效编号、默认持有、活动服装、试用时长和 Spine 皮肤映射。
## 每日轮换按本地日期计算，可跳过已持有服装；目录本身不写入玩家存档。

class_name CostumeCatalog
extends RefCounted

const TRIAL_THRESHOLD: int = 2

const DEFAULT_COSTUME_ID: int = 1

const TRIAL_COSTUME_IDS: Array[int] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

const EVENT_COSTUME_IDS: Array[int] = [16]

const HALLOWEEN_COSTUME_ID: int = 16

const _EVENT_ASSET_INDEX: Dictionary = {16: 15}

const _INITIAL_SKIN_NAME: String = "0"

const _DEFAULT_SKIN_NAME: String = "default"

const TRIAL_DURATION_SEC: int = 24 * 60 * 60

const DAY_ANCHOR_YEAR: int = 2026
const DAY_ANCHOR_MONTH: int = 4
const DAY_ANCHOR_DAY: int = 21

static var debug_day_override: int = -1


static func is_valid(id: int) -> bool:
	return id == DEFAULT_COSTUME_ID or TRIAL_COSTUME_IDS.has(id) or EVENT_COSTUME_IDS.has(id)


static func is_event(id: int) -> bool:
	return EVENT_COSTUME_IDS.has(id)


static func is_default_owned(id: int) -> bool:
	return id > 0 and id < TRIAL_THRESHOLD


static func is_trial(id: int) -> bool:
	return id >= TRIAL_THRESHOLD and TRIAL_COSTUME_IDS.has(id)


static func asset_index(id: int) -> int:
	if is_event(id):
		return int(_EVENT_ASSET_INDEX.get(id, 0))
	return id - 1


const _SPINE_SKIN_BY_ASSET_INDEX: Dictionary = {
	1: "4",
	2: "5",
	3: "3",
	4: "11",
	5: "2",
	6: "10",
	7: "8",
	8: "14",
	9: "7",
	10: "6",
	11: "1",
	12: "9",
	13: "12",
	14: "13",
	15: "15",
}


static func skin_for(id: int) -> String:
	if id == DEFAULT_COSTUME_ID:
		return _INITIAL_SKIN_NAME
	if not is_valid(id):
		return _DEFAULT_SKIN_NAME
	return str(_SPINE_SKIN_BY_ASSET_INDEX.get(asset_index(id), _DEFAULT_SKIN_NAME))


static func all_ids() -> Array[int]:
	var ids: Array[int] = [DEFAULT_COSTUME_ID]
	ids.append_array(TRIAL_COSTUME_IDS)
	return ids


static func costume_for_day(day_offset: int) -> int:
	var pool_size: int = TRIAL_COSTUME_IDS.size()
	if pool_size <= 0:
		return DEFAULT_COSTUME_ID

	var idx: int = posmod(day_offset, pool_size)
	return TRIAL_COSTUME_IDS[idx]


## 从日期决定的起点轮换候选并跳过已持有项；同一天和同一持有集合得到稳定结果。
static func costume_for_day_skipping(day_offset: int, held_ids: Array[int]) -> int:
	var pool_size: int = TRIAL_COSTUME_IDS.size()
	if pool_size <= 0:
		return DEFAULT_COSTUME_ID
	var start_idx: int = posmod(day_offset, pool_size)
	for step in pool_size:
		var candidate: int = TRIAL_COSTUME_IDS[(start_idx + step) % pool_size]
		if not held_ids.has(candidate):
			return candidate

	return TRIAL_COSTUME_IDS[start_idx]


## 把本地日历日期转成连续天数，用来驱动每日轮换而不是按进程运行时长轮换。
static func today_day_offset() -> int:
	if debug_day_override >= 0:
		return debug_day_override
	var dt: Dictionary = Time.get_date_dict_from_system()
	var jdn_today: int = _local_date_to_jdn(
		int(dt.get("year", DAY_ANCHOR_YEAR)),
		int(dt.get("month", DAY_ANCHOR_MONTH)),
		int(dt.get("day", DAY_ANCHOR_DAY))
	)
	var jdn_anchor: int = _local_date_to_jdn(DAY_ANCHOR_YEAR, DAY_ANCHOR_MONTH, DAY_ANCHOR_DAY)
	return maxi(0, jdn_today - jdn_anchor)


static func today_costume() -> int:
	return costume_for_day(today_day_offset())


static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	@warning_ignore("integer_division")
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	@warning_ignore("integer_division")
	var jdn: int = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
	return jdn
