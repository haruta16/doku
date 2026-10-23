## 问题题目后置工厂：只在指定关段把命中筛选谓词的题目稳定移到队尾。
class_name TailSortedBankCursorFactory
extends RefCounted


## 关号未进入指定区间时使用普通游标，否则创建按谓词后置的游标。
static func create(
	level_num: int,
	sz: int,
	rank: int,
	tier: String,
	pools: Dictionary,
	seg_min: int,
	seg_max: int,
	is_bad: Callable
) -> BankCursor:
	if level_num < seg_min or level_num > seg_max:
		return BankCursor.create(level_num, sz, rank, tier, pools)
	if level_num >= 51:
		return TailSortedMainBankCursor.new(sz, rank, tier, level_num, pools, is_bad)
	return TailSortedLegacyBankCursor.new(sz, rank, tier, level_num, pools, is_bad)


## 分别收集正常与命中谓词的题目索引，保留各组原序后拼接。
static func partition_indices(entries: Array, is_bad: Callable) -> PackedInt32Array:
	var good: PackedInt32Array = PackedInt32Array()
	var bad: PackedInt32Array = PackedInt32Array()
	var usable: bool = is_bad.is_valid()
	for i: int in range(entries.size()):
		if usable and bool(is_bad.call(entries[i] as Dictionary)):
			bad.append(i)
		else:
			good.append(i)
	good.append_array(bad)
	return good
