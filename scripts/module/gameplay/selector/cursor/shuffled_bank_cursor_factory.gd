## 种子洗牌游标工厂：将用户种子与题池身份组合，生成可复现的题目索引排列。
class_name ShuffledBankCursorFactory
extends RefCounted


## 按关号创建旧路径或主线路径的种子洗牌游标。
static func create(
	level_num: int, sz: int, rank: int, tier: String, pools: Dictionary, user_seed: int
) -> BankCursor:
	if level_num >= 51:
		return ShuffledMainBankCursor.new(sz, rank, tier, level_num, pools, user_seed)
	return ShuffledLegacyBankCursor.new(sz, rank, tier, level_num, pools, user_seed)


## 对连续索引执行固定种子的 Fisher–Yates 洗牌，空题池返回空排列。
static func build_perm(total: int, perm_seed_value: int) -> PackedInt32Array:
	var perm: PackedInt32Array = PackedInt32Array()
	if total <= 0:
		return perm
	perm.resize(total)
	for i: int in range(total):
		perm[i] = i
	if total <= 1:
		return perm
	var rng := RandomNumberGenerator.new()
	rng.seed = perm_seed_value
	for i: int in range(total - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = perm[i]
		perm[i] = perm[j]
		perm[j] = tmp
	return perm


## 组合用户种子、尺寸层级档位及各来源数量，得到主题库排列种子。
static func perm_seed(
	user_seed: int,
	sz: int,
	rank: int,
	tier: String,
	total_regular: int,
	total_lkstyle: int,
	total_gc: int
) -> int:
	return hash([user_seed, "combined", sz, rank, tier, total_regular, total_lkstyle, total_gc])


## 为 LK 改题库独立计算排列种子，避免与主题库共享同一随机序列。
static func lkmod_perm_seed(user_seed: int, sz: int, rank: int, lk_total: int) -> int:
	return hash([user_seed, "lkmod", sz, rank, lk_total])
