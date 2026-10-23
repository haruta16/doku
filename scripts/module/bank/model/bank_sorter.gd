## 题库节奏排序：按实验组的节奏分数产生索引排列，题目内容仍由 BankData 管理。
class_name BankSorter
extends RefCounted

const _GROUP_CONTROL: int = 0

static var _sort_cache: Dictionary = {}


## 合并 regular、lkstyle、gc 的索引空间，按节奏降序排序并缓存；对照组保持原序。
static func get_sorted_indices_for_combined(
	sz: int,
	rank: int,
	tier: String,
	total_regular: int,
	total_lkstyle: int,
	total_gc: int,
	ab_group: int
) -> PackedInt32Array:
	var total: int = total_regular + total_lkstyle + total_gc
	if ab_group == _GROUP_CONTROL or total == 0:
		return _identity(total)

	var key: String = (
		"combined|%d|%d|%s|%d|%d|%d|%d"
		% [sz, rank, tier, total_regular, total_lkstyle, total_gc, ab_group]
	)
	if _sort_cache.has(key):
		return _sort_cache[key]

	var scores: Array = []
	scores.resize(total)
	for g in range(total):
		var pace: Dictionary
		if g < total_regular:
			pace = BankData.get_pace_entry("regular", sz, rank, g)
		elif g < total_regular + total_lkstyle:
			pace = BankData.get_pace_entry("lkstyle", sz, rank, g - total_regular)
		else:
			pace = BankData.get_pace_entry("gc", sz, rank, g - total_regular - total_lkstyle)
		scores[g] = [g, _pick_score(pace, ab_group)]

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	_stable_desc_sort_with_ties_shuffle(scores, rng)

	var out := PackedInt32Array()
	out.resize(total)
	for i in range(total):
		out[i] = scores[i][0]
	_sort_cache[key] = out
	return out


## 对传入节奏数组生成索引排列；缓存键同时作为随机种子，保证同键顺序稳定。
static func get_sorted_indices_from_pace_array(
	pace_array: Array, ab_group: int, cache_key: String
) -> PackedInt32Array:
	var total: int = pace_array.size()
	if ab_group == _GROUP_CONTROL or total == 0:
		return _identity(total)

	if _sort_cache.has(cache_key):
		return _sort_cache[cache_key]

	var scores: Array = []
	scores.resize(total)
	for i in range(total):
		scores[i] = [i, _pick_score(pace_array[i], ab_group)]

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cache_key)
	_stable_desc_sort_with_ties_shuffle(scores, rng)

	var out := PackedInt32Array()
	out.resize(total)
	for i in range(total):
		out[i] = scores[i][0]
	_sort_cache[cache_key] = out
	return out


## 把合并后的全局索引还原为题库来源和该来源内的局部索引。
static func decode_global_idx(
	global_idx: int, total_regular: int, total_lkstyle: int, total_gc: int
) -> Dictionary:
	if global_idx < total_regular:
		return {"source": "regular", "local_idx": global_idx}
	if global_idx < total_regular + total_lkstyle:
		return {"source": "lkstyle", "local_idx": global_idx - total_regular}
	return {"source": "gc", "local_idx": global_idx - total_regular - total_lkstyle}


## 清空排序缓存，使后续请求重新读取节奏分数。
static func clear_cache() -> void:
	_sort_cache.clear()


## 提供实验组节奏分数的公共入口，缺少有效步骤序列时返回零。
static func pick_score(pace: Dictionary, group: int) -> float:
	return _pick_score(pace, group)


## 输出排序前若干项的来源、索引和分数，用于核对选题顺序。
static func debug_dump_combined(
	sz: int,
	rank: int,
	tier: String,
	total_regular: int,
	total_lkstyle: int,
	total_gc: int,
	ab_group: int,
	limit: int = 20
) -> String:
	var sorted := get_sorted_indices_for_combined(
		sz, rank, tier, total_regular, total_lkstyle, total_gc, ab_group
	)
	var lines: Array[String] = []
	lines.append(
		(
			"[BankSorter] combined sz=%d rank=%d tier=%s group=%d total=%d"
			% [sz, rank, tier, ab_group, sorted.size()]
		)
	)
	var n: int = min(limit, sorted.size())
	for i in range(n):
		var g: int = sorted[i]
		var dec := decode_global_idx(g, total_regular, total_lkstyle, total_gc)
		var pace := BankData.get_pace_entry(dec["source"], sz, rank, dec["local_idx"])
		var score := _pick_score(pace, ab_group)
		lines.append(
			(
				"  #%d: global=%d src=%s local=%d score=%.4f"
				% [i, g, dec["source"], dec["local_idx"], score]
			)
		)
	return "\n".join(lines)


## 生成未排序的连续索引，供对照组和空题库使用。
static func _identity(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(n)
	for i in range(n):
		out[i] = i
	return out


## 仅接受有解题步骤序列的节奏记录，按实验组读取 g1～g4。
static func _pick_score(pace: Dictionary, group: int) -> float:
	if pace.is_empty():
		return 0.0
	if not pace.has("r_seq"):
		return 0.0
	var r_seq_val: Variant = pace["r_seq"]
	if not r_seq_val is Array or (r_seq_val as Array).is_empty():
		return 0.0
	match group:
		1:
			return float(pace.get("g1", 0.0))
		2:
			return float(pace.get("g2", 0.0))
		3:
			return float(pace.get("g3", 0.0))
		4:
			return float(pace.get("g4", 0.0))
	return 0.0


## 先按分数降序排列，再用传入随机数生成器打乱近似同分段。
static func _stable_desc_sort_with_ties_shuffle(pairs: Array, rng: RandomNumberGenerator) -> void:
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])

	var i: int = 0
	var n: int = pairs.size()
	var eps: float = 1e-09
	while i < n:
		var j: int = i + 1
		while j < n and abs(pairs[j][1] - pairs[i][1]) < eps:
			j += 1
		if j - i > 1:
			for k in range(j - 1, i, -1):
				var swap_i: int = rng.randi_range(i, k)
				if swap_i != k:
					var tmp = pairs[k]
					pairs[k] = pairs[swap_i]
					pairs[swap_i] = tmp
		i = j
