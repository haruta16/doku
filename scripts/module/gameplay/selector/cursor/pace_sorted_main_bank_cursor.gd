## 主线节奏排序游标：分别排序主题库与 LK 改题库，再按交付间隔选择对应排列。
class_name PaceSortedMainBankCursor
extends MainBankCursor

var _pace_group: int
var _strict_rank: bool

var _sorted_combined: PackedInt32Array

var _sorted_lkmod: PackedInt32Array

var _lk_mod_pace: Array = []


## 初始化基础游标和节奏实验参数，再建立对应排序缓存。
func _init(
	sz: int,
	rank: int,
	tier: String,
	level_num: int,
	pools: Dictionary,
	pace_group: int,
	strict_rank: bool
) -> void:
	super._init(sz, rank, tier, level_num, pools)
	_pace_group = pace_group
	_strict_rank = strict_rank
	_rebuild_lkmod_pace(pools)
	_rebuild_sort()


## 先取得基础游标位置，再映射为节奏排序后的题目索引并附分数。
func pos() -> Dictionary:
	var base: Dictionary = super.pos()
	if not bool(base.get("is_main_path", false)):
		return base
	var since_lk: int = int(base.get("since_lk", 0))
	var base_lk_idx: int = int(base.get("lk_idx", 0))
	var lk_total: int = _lk_mod_pace.size()

	if (
		since_lk >= 4
		and base_lk_idx < lk_total
		and not _sorted_lkmod.is_empty()
		and base_lk_idx < _sorted_lkmod.size()
	):
		var mapped_lk: int = _sorted_lkmod[base_lk_idx]
		base["lk_idx"] = mapped_lk
		base["_pace_group"] = _pace_group
		base["_pace_score"] = _score_for_lkmod(mapped_lk)
		return base

	if _sorted_combined.is_empty():
		return base
	var base_idx: int = int(base.get("idx", 0))
	if base_idx < 0 or base_idx >= _sorted_combined.size():
		return base
	var mapped_global: int = _sorted_combined[base_idx]
	base["idx"] = mapped_global
	base["_pace_group"] = _pace_group
	base["_pace_score"] = _score_for_combined(mapped_global)
	return base


## 题池变化时刷新基础游标与节奏排序，使索引继续对齐。
func rebind_pools(pools: Dictionary) -> void:
	super.rebind_pools(pools)
	_rebuild_lkmod_pace(pools)
	_rebuild_sort()


## 调用 BankSorter 重建当前题池的节奏索引排列。
func _rebuild_sort() -> void:
	_sorted_combined = BankSorter.get_sorted_indices_for_combined(
		_sz, _rank, _tier, _total_regular, _total_lkstyle, _total_gc, _pace_group
	)

	var cache_key: String = "lkmod|%d|%d|%d" % [_sz, _rank, hash(_lk_mod_pace)]
	_sorted_lkmod = BankSorter.get_sorted_indices_from_pace_array(
		_lk_mod_pace, _pace_group, cache_key
	)


## 按相同过滤规则重建 LK 节奏数组，条数不一致时报告并放弃该节奏排列。
func _rebuild_lkmod_pace(pools: Dictionary) -> void:
	_lk_mod_pace = PaceLkModPaceCollector.collect(_sz, _rank, _strict_rank)
	var pool_lk_mod: Array = pools.get("lk_mod", [])
	if _lk_mod_pace.size() != pool_lk_mod.size():
		push_error(
			(
				"PaceSortedMainBankCursor: lk_mod_pace(%d) 与 pools.lk_mod(%d) 不对齐,过滤规则漂移"
				% [_lk_mod_pace.size(), pool_lk_mod.size()]
			)
		)
		_lk_mod_pace = []


## 把主题库拼接索引映射回来源，取得当前实验组节奏分数。
func _score_for_combined(g: int) -> float:
	var source: String
	var local_idx: int
	if g < _total_regular:
		source = "regular"
		local_idx = g
	elif g < _total_regular + _total_lkstyle:
		source = "lkstyle"
		local_idx = g - _total_regular
	else:
		source = "gc"
		local_idx = g - _total_regular - _total_lkstyle
	var pace_entry: Dictionary = BankData.get_pace_entry(source, _sz, _rank, local_idx)
	return BankSorter.pick_score(pace_entry, _pace_group)


## 读取映射后 LK 题目的节奏分，索引越界返回零。
func _score_for_lkmod(mapped_lk_idx: int) -> float:
	if mapped_lk_idx < 0 or mapped_lk_idx >= _lk_mod_pace.size():
		return 0.0
	return BankSorter.pick_score(_lk_mod_pace[mapped_lk_idx], _pace_group)
