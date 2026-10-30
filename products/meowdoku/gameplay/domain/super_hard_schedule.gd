## 超难关排程：从第 35 关起每十关出现一次，题库用完后切换几何变换继续循环。
class_name SuperHardSchedule
extends RefCounted

const MIN_LEVEL: int = 35

const PHASE: int = 5

const PERIOD: int = 10


## 同时检查起始关号和周期余数，判断是否轮到超难关。
static func is_super_hard(level_num: int) -> bool:
	return level_num >= MIN_LEVEL and level_num % PERIOD == PHASE


## 把超难关关号换成从第 35 关起计算的序号。
static func ordinal(level_num: int) -> int:
	return (level_num - MIN_LEVEL) / PERIOD


## 相对锚点计算题库索引和变换编号，空题库返回零索引与零变换。
static func bank_pos(level_num: int, anchor_level: int, total: int) -> Dictionary:
	if total <= 0:
		return {"idx": 0, "transform": 0}
	var seq: int = ordinal(level_num) - ordinal(anchor_level)
	return {
		"idx": posmod(seq, total),
		"transform": posmod(seq / total, LevelData.TRANSFORM_COUNT),
	}
