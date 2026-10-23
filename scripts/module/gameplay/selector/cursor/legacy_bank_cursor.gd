## 前期顺序题库游标：将已保存索引映射到常规、LK 风格与 GC 拼接题池，不使用几何轮换。
class_name LegacyBankCursor
extends BankCursor

var _total: int


## 保存尺寸层级及关号，并计算拼接题池总长度。
func _init(sz: int, rank: int, tier: String, level_num: int, pools: Dictionary) -> void:
	_sz = sz
	_rank = rank
	_tier = tier
	_level_num = level_num
	_total = _pool_total(pools)


## 用存档游标对题池长度取模，返回旧路径的位置结构。
func pos() -> Dictionary:
	var idx: int = GameState.get_bank_index(_sz, _rank, _tier)
	return {
		"idx": idx % _total if _total > 0 else 0,
		"since_lk": 0,
		"transform": 0,
		"lk_idx": 0,
		"is_main_path": false,
	}


## 只增加旧题库游标，暂不落盘。
func advance(entry: Dictionary) -> void:
	GameState.advance_bank_index(_sz, _rank, _tier, false)


## 题池改变后刷新总长度。
func rebind_pools(pools: Dictionary) -> void:
	_total = _pool_total(pools)


## 返回完整拼接题池的题数作为扫描预算。
func budget() -> int:
	return _total


## 合计 regular、lkstyle 与 gc 三个来源的题数。
func _pool_total(pools: Dictionary) -> int:
	return (
		(pools.get("regular", []) as Array).size()
		+ (pools.get("lkstyle", []) as Array).size()
		+ (pools.get("gc", []) as Array).size()
	)
