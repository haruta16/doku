## 主线索引映射游标：以固定种子洗牌改写出题顺序，存档仍保存基础游标进度。
class_name ShuffledMainBankCursor
extends MainBankCursor

var _user_seed: int

var _perm_combined: PackedInt32Array

var _perm_lkmod: PackedInt32Array


## 初始化基础游标及映射参数，再建立本题池的索引排列。
func _init(
	sz: int, rank: int, tier: String, level_num: int, pools: Dictionary, user_seed: int
) -> void:
	super._init(sz, rank, tier, level_num, pools)
	_user_seed = user_seed
	_rebuild_perm(pools)


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
		and not _perm_lkmod.is_empty()
		and base_lk_idx < _perm_lkmod.size()
	):
		base["lk_idx"] = _perm_lkmod[base_lk_idx]
		return base

	if _perm_combined.is_empty():
		return base
	var base_idx: int = int(base.get("idx", 0))
	if base_idx < 0 or base_idx >= _perm_combined.size():
		return base
	base["idx"] = _perm_combined[base_idx]
	return base


## 题池过滤或重建后刷新基础状态与索引排列。
func rebind_pools(pools: Dictionary) -> void:
	super.rebind_pools(pools)
	_rebuild_perm(pools)


## 用用户种子重建来源排列；零种子时清映射并保留原序。
func _rebuild_perm(pools: Dictionary) -> void:
	if _user_seed == 0:
		_perm_combined = PackedInt32Array()
		_perm_lkmod = PackedInt32Array()
		return
	var tr: int = (pools.get("regular", []) as Array).size()
	var tl: int = (pools.get("lkstyle", []) as Array).size()
	var tg: int = (pools.get("gc", []) as Array).size()
	var lk: int = (pools.get("lk_mod", []) as Array).size()
	_perm_combined = ShuffledBankCursorFactory.build_perm(
		tr + tl + tg, ShuffledBankCursorFactory.perm_seed(_user_seed, _sz, _rank, _tier, tr, tl, tg)
	)
	_perm_lkmod = ShuffledBankCursorFactory.build_perm(
		lk, ShuffledBankCursorFactory.lkmod_perm_seed(_user_seed, _sz, _rank, lk)
	)
