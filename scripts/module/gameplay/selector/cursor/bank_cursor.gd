## 题库游标基类：统一预览位置、推进和预算接口，第 51 关起采用带变换轮换的主线游标。
class_name BankCursor
extends RefCounted

var _sz: int
var _rank: int
var _tier: String
var _level_num: int


## 按关号在旧顺序游标和主线循环游标之间选择。
static func create(
	level_num: int, sz: int, rank: int, tier: String, pools: Dictionary
) -> BankCursor:
	if level_num >= 51:
		return MainBankCursor.new(sz, rank, tier, level_num, pools)
	return LegacyBankCursor.new(sz, rank, tier, level_num, pools)


## 基类不提供位置，具体游标应重写此方法。
func pos() -> Dictionary:
	return {}


## 基类推进为空操作，具体游标负责更新相应进度。
func advance(_entry: Dictionary) -> void:
	pass


## 题池变化时的扩展入口，基类无需处理。
func rebind_pools(_pools: Dictionary) -> void:
	pass


## 基类扫描预算为零，具体游标按题池规模计算。
func budget() -> int:
	return 0
