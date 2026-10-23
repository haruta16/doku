## 前期节奏排序游标：把顺序索引映射到节奏排列，保留旧游标的推进方式。
class_name PaceSortedLegacyBankCursor
extends LegacyBankCursor

var _pace_group: int
var _sorted_indices: PackedInt32Array
var _total_regular: int
var _total_lkstyle: int
var _total_gc: int


## 初始化基础游标和节奏实验参数，再建立对应排序缓存。
func _init(
	sz: int, rank: int, tier: String, level_num: int, pools: Dictionary, pace_group: int
) -> void:
	super._init(sz, rank, tier, level_num, pools)
	_pace_group = pace_group
	_capture_pool_sizes(pools)
	_rebuild_sort()


## 先取得基础游标位置，再映射为节奏排序后的题目索引并附分数。
func pos() -> Dictionary:
	var base: Dictionary = super.pos()
	if _sorted_indices.is_empty():
		return base
	var base_idx: int = int(base.get("idx", 0))
	if base_idx < 0 or base_idx >= _sorted_indices.size():
		return base

	var mapped_global: int = _sorted_indices[base_idx]
	base["idx"] = mapped_global
	base["_pace_group"] = _pace_group
	base["_pace_score"] = _score_for_mapped_global(mapped_global)
	return base


## 题池变化时刷新基础游标与节奏排序，使索引继续对齐。
func rebind_pools(pools: Dictionary) -> void:
	super.rebind_pools(pools)
	_capture_pool_sizes(pools)
	_rebuild_sort()


## 保存三个普通来源的题数，供全局索引还原。
func _capture_pool_sizes(pools: Dictionary) -> void:
	_total_regular = (pools.get("regular", []) as Array).size()
	_total_lkstyle = (pools.get("lkstyle", []) as Array).size()
	_total_gc = (pools.get("gc", []) as Array).size()


## 调用 BankSorter 重建当前题池的节奏索引排列。
func _rebuild_sort() -> void:
	_sorted_indices = BankSorter.get_sorted_indices_for_combined(
		_sz, _rank, _tier, _total_regular, _total_lkstyle, _total_gc, _pace_group
	)


## 把映射后的全局索引还原为来源局部索引，再读取节奏评分。
func _score_for_mapped_global(g: int) -> float:
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
