## 第 51 关后主线游标：记录主题库位置、LK 间隔和几何变换轮次，试选时只更新内存。
class_name MainBankCursor
extends BankCursor

var _total_regular: int
var _total_lkstyle: int
var _total_gc: int
var _total_lk_mod: int


## 绑定来源题数，兼容旧进度初始化并处理整库轮换。
func _init(sz: int, rank: int, tier: String, level_num: int, pools: Dictionary) -> void:
	_sz = sz
	_rank = rank
	_tier = tier
	_level_num = level_num
	_bind_pool_sizes(pools)
	_ensure_seeded()
	_ensure_rollover()


## 返回主题库索引、LK 插入间隔、变换编号与 LK 独立索引。
func pos() -> Dictionary:
	_ensure_rollover()
	var prog: Dictionary = GameState.get_main_progress(_sz, _rank, _tier)
	var idx: int = prog.get("idx", 0)
	var since_lk: int = prog.get("since_lk", 0)
	var transform: int = prog.get("transform", 0)
	var lkprog: Dictionary = GameState.get_lkmod_progress(_sz, _rank)
	var lk_idx: int = lkprog.get("idx", 0)
	return {
		"idx": idx,
		"since_lk": since_lk,
		"transform": transform,
		"lk_idx": lk_idx,
		"is_main_path": true,
	}


## 按实际来源推进相应游标，并更新距上次 LK 的间隔，留给最终交付统一写盘。
func advance(entry: Dictionary) -> void:
	var src_main: String = entry.get("_bank_source_main", "")
	if src_main == "lk_mod":
		var lkprog: Dictionary = GameState.get_lkmod_progress(_sz, _rank)
		lkprog["idx"] = lkprog.get("idx", 0) + 1
		GameState.set_lkmod_progress(_sz, _rank, lkprog, false)
		var prog: Dictionary = GameState.get_main_progress(_sz, _rank, _tier)
		prog["since_lk"] = 0
		GameState.set_main_progress(_sz, _rank, _tier, prog, false)
	else:
		var prog: Dictionary = GameState.get_main_progress(_sz, _rank, _tier)
		prog["idx"] = prog.get("idx", 0) + 1
		prog["since_lk"] = prog.get("since_lk", 0) + 1
		GameState.set_main_progress(_sz, _rank, _tier, prog, false)


## 题池过滤后重新统计大小并校正跨轮进度。
func rebind_pools(pools: Dictionary) -> void:
	_bind_pool_sizes(pools)
	_ensure_rollover()


## 按所有来源题数乘八种变换给出候选扫描上限。
func budget() -> int:
	var main_total: int = _total_regular + _total_lkstyle + _total_gc + _total_lk_mod
	return main_total * LevelData.TRANSFORM_COUNT


## 记录四个来源的题目数量，避免后续反复计算。
func _bind_pool_sizes(pools: Dictionary) -> void:
	_total_regular = (pools.get("regular", []) as Array).size()
	_total_lkstyle = (pools.get("lkstyle", []) as Array).size()
	_total_gc = (pools.get("gc", []) as Array).size()
	_total_lk_mod = (pools.get("lk_mod", []) as Array).size()


## 尚未建立主线索引时用旧题库索引初始化，避免升级后无条件从头重来。
func _ensure_seeded() -> void:
	var prog: Dictionary = GameState.get_main_progress(_sz, _rank, _tier)
	var idx: int = prog.get("idx", -1)
	if idx >= 0:
		return
	var legacy_idx: int = GameState.get_bank_index(_sz, _rank, _tier)
	var denom: int = _total_regular + _total_lkstyle
	idx = legacy_idx % denom if (legacy_idx > 0 and denom > 0) else 0
	prog["idx"] = idx
	prog["since_lk"] = 0
	GameState.set_main_progress(_sz, _rank, _tier, prog, false)


## 主题库索引用尽后归零，切到下一种几何变换并重置 LK 间隔。
func _ensure_rollover() -> void:
	var prog: Dictionary = GameState.get_main_progress(_sz, _rank, _tier)
	var idx: int = prog.get("idx", 0)
	var main_total: int = _total_regular + _total_lkstyle + _total_gc
	if main_total <= 0 or idx < main_total:
		return
	var transform: int = prog.get("transform", 0)
	transform = (transform + 1) % LevelData.TRANSFORM_COUNT
	prog = {"idx": 0, "since_lk": 0, "transform": transform}
	GameState.set_main_progress(_sz, _rank, _tier, prog, false)
