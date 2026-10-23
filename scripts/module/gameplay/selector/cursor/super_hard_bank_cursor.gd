## 超难题库游标：由关号和锚点直接推导位置，推进候选不会修改常规题库进度。
class_name SuperHardBankCursor
extends BankCursor

var _total: int
var _anchor_level: int


## 保存超难关与锚点，绑定统一题池中 regular 槽的总题数。
func _init(level_num: int, anchor_level: int, pools: Dictionary) -> void:
	_sz = SuperHardModifier.SIZE

	_rank = 0
	_tier = ""
	_level_num = level_num
	_anchor_level = anchor_level
	_bind_pool_sizes(pools)


## 通过 SuperHardSchedule 返回对应题目索引和几何变换。
func pos() -> Dictionary:
	var p: Dictionary = SuperHardSchedule.bank_pos(_level_num, _anchor_level, _total)
	return {
		"idx": int(p.get("idx", 0)),
		"since_lk": 0,
		"transform": int(p.get("transform", 0)),
		"lk_idx": 0,
		"is_main_path": true,
	}


## 位置由超难关关号决定，此处不累加存档游标。
func advance(_entry: Dictionary) -> void:
	pass


## 重新绑定超难题池的总题数。
func rebind_pools(pools: Dictionary) -> void:
	_bind_pool_sizes(pools)


## 返回题数乘八种变换的扫描预算。
func budget() -> int:
	return _total * LevelData.TRANSFORM_COUNT


## 读取统一题池 regular 槽中的超难题数量。
func _bind_pool_sizes(pools: Dictionary) -> void:
	_total = (pools.get("regular", []) as Array).size()
