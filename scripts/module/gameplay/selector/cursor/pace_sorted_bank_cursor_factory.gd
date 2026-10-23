## 节奏游标工厂：读取当前节奏实验组，再选择前期或主线排序游标。
class_name PaceSortedBankCursorFactory
extends RefCounted


## 按第 51 关分界创建节奏排序游标，并向主线路径传递严格层级过滤选项。
static func create(
	level_num: int, sz: int, rank: int, tier: String, pools: Dictionary, strict_rank: bool
) -> BankCursor:
	var pace_group: int = ABTestManager.normal_level.get_pace_group()
	if level_num >= 51:
		return PaceSortedMainBankCursor.new(
			sz, rank, tier, level_num, pools, pace_group, strict_rank
		)
	return PaceSortedLegacyBankCursor.new(sz, rank, tier, level_num, pools, pace_group)
