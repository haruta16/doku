## 按主线关号命中预设特殊关表，从 sp 或 lk 题库取指定序号的题。
class_name SpecialProvider
extends LevelProvider

const SPECIAL_LEVELS: Dictionary = {
	10: {"source": "sp", "index": 44},
	20: {"source": "sp", "index": 45},
	30: {"source": "sp", "index": 36},
	40: {"source": "sp", "index": 9},
	50: {"source": "sp", "index": 37},
	55: {"source": "sp", "index": 7},
	60: {"source": "sp", "index": 34},
	62: {"source": "sp", "index": 8},
	70: {"source": "sp", "index": 32},
	75: {"source": "sp", "index": 6},
	80: {"source": "sp", "index": 43},
	90: {"source": "sp", "index": 33},
	100: {"source": "sp", "index": 5},
	123: {"source": "sp", "index": 1},
	200: {"source": "lk", "index": 30},
	250: {"source": "lk", "index": 75},
	314: {"source": "lk", "index": 141},
	456: {"source": "sp", "index": 2},
}


## 返回固定特殊关来源的标识。
func get_provider_id() -> StringName:
	return &"special"


## 只有当前关号出现在特殊关表中才可用。
func is_available(ctx: LevelSelectContext) -> bool:
	return SPECIAL_LEVELS.has(ctx.level_num)


## 将表中的一基题号换成数组索引，展开题目并附加原题库来源信息。
func next_entry(ctx: LevelSelectContext) -> Dictionary:
	var spec: Dictionary = SPECIAL_LEVELS[ctx.level_num]
	var idx: int = spec["index"] - 1
	if spec["source"] == "sp":
		var sp_levels: Array = BankData.get_sp_levels()
		if idx >= 0 and idx < sp_levels.size():
			var entry: Dictionary = BankData.materialize_entry(sp_levels[idx])
			entry["_bank_source"] = "sp"
			entry["_bank_idx"] = idx + 1
			entry["_bank_tier"] = ""
			entry["_bank_rank"] = entry.get("r", 1)
			return entry
	elif spec["source"] == "lk":
		var lk_levels: Array = BankData.get_lk_levels()
		if idx >= 0 and idx < lk_levels.size():
			var entry: Dictionary = BankData.materialize_entry(lk_levels[idx])
			entry["_bank_source"] = "lk"
			entry["_bank_idx"] = idx + 1
			entry["_bank_tier"] = ""
			entry["_bank_rank"] = entry.get("maxR", 1)
			return entry
	return {}
