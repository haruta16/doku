## 前期索引映射游标：以问题题目稳定后置改写出题顺序，存档仍保存基础游标进度。
class_name TailSortedLegacyBankCursor
extends LegacyBankCursor

var _is_bad: Callable

var _sorted: PackedInt32Array


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
	if _sorted.is_empty():
		return base
	var base_idx: int = int(base.get("idx", 0))
	if base_idx < 0 or base_idx >= _sorted.size():
		return base
	base["idx"] = _sorted[base_idx]
	return base


## 题池过滤或重建后刷新基础状态与索引排列。
func rebind_pools(pools: Dictionary) -> void:
	super.rebind_pools(pools)
	_rebuild_sort(pools)


## 合并 regular、lkstyle 和 gc 来源，再按问题题谓词稳定分区。
func _rebuild_sort(pools: Dictionary) -> void:
	var combined: Array = []
	combined.append_array(pools.get("regular", []))
	combined.append_array(pools.get("lkstyle", []))
	combined.append_array(pools.get("gc", []))
	_sorted = TailSortedBankCursorFactory.partition_indices(combined, _is_bad)
