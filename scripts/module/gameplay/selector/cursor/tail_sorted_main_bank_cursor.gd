## 主线索引映射游标：以问题题目稳定后置改写出题顺序，存档仍保存基础游标进度。
class_name TailSortedMainBankCursor
extends MainBankCursor

var _is_bad: Callable

var _sorted_combined: PackedInt32Array

var _sorted_lkmod: PackedInt32Array


## 初始化基础游标及映射参数，再建立本题池的索引排列。
func _init(
	sz: int, rank: int, tier: String, level_num: int, pools: Dictionary, is_bad: Callable
) -> void:
	super._init(sz, rank, tier, level_num, pools)
	_is_bad = is_bad
	_rebuild_sort(pools)


## 保留基础游标状态，仅把所选来源的位置映射到排列后的题目索引。
func pos() -> Dictionary:
	var base: Dictionary = super.pos()
	if not bool(base.get("is_main_path", false)):
		return base
	var since_lk: int = int(base.get("since_lk", 0))
	var base_lk_idx: int = int(base.get("lk_idx", 0))

	if (
		since_lk >= 4
		and base_lk_idx < _total_lk_mod
		and not _sorted_lkmod.is_empty()
		and base_lk_idx < _sorted_lkmod.size()
	):
		base["lk_idx"] = _sorted_lkmod[base_lk_idx]
		return base

	if _sorted_combined.is_empty():
		return base
	var base_idx: int = int(base.get("idx", 0))
	if base_idx < 0 or base_idx >= _sorted_combined.size():
		return base
	base["idx"] = _sorted_combined[base_idx]
	return base


## 题池过滤或重建后刷新基础状态与索引排列。
func rebind_pools(pools: Dictionary) -> void:
	super.rebind_pools(pools)
	_rebuild_sort(pools)


## 合并普通来源后按谓词稳定分区；主线路径同时为 LK 改题库建立独立排列。
func _rebuild_sort(pools: Dictionary) -> void:
	var combined: Array = []
	combined.append_array(pools.get("regular", []))
	combined.append_array(pools.get("lkstyle", []))
	combined.append_array(pools.get("gc", []))
	_sorted_combined = TailSortedBankCursorFactory.partition_indices(combined, _is_bad)
	_sorted_lkmod = TailSortedBankCursorFactory.partition_indices(pools.get("lk_mod", []), _is_bad)
