## 实验组题目过滤条件：根据解题步骤指标识别需要跳过的题目，不修改题库内容。
class_name BadLevelPredicates
extends RefCounted

const R4_RATIO_THRESHOLD: float = 0.3


## 总步骤有效时，检查 R4 步骤占比是否超过 30%。
static func is_bad_11703(entry: Dictionary) -> bool:
	var steps: int = int(entry.get("steps", 0))
	if steps <= 0:
		return false
	return float(int(entry.get("r4", 0))) / float(steps) > R4_RATIO_THRESHOLD


## 只针对 R2、R3 题目，检查开头 R1 步骤数是否达到棋盘边长。
static func is_bad_11702(entry: Dictionary, sz: int) -> bool:
	var r: int = int(entry.get("r", 0))
	if r != 2 and r != 3:
		return false
	if not entry.has("leadR1"):
		return false
	return int(entry.get("leadR1", 0)) >= sz
