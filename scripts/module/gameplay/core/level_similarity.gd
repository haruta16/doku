## 解题风格相似度：结合步骤组成与顺序特征，限制最近题目窗口中重复风格的组数。
class_name LevelSimilarity
extends RefCounted

const SAME_STYLE_THRESHOLD: float = 0.932
const HIST_DIM: int = 5
const ORDER_DIM: int = 8


## 读取五维步骤直方图和八维顺序向量，兼容紧凑数组；维度不符返回空字典。
static func extract_vec(entry: Dictionary) -> Dictionary:
	var hist_value: Variant = entry.get("stepHist", [])
	var order_value: Variant = entry.get("stepOrderZ", [])
	var hist: Array = (
		Array(hist_value)
		if hist_value is PackedInt32Array
		else (hist_value as Array if hist_value is Array else [])
	)
	var order_z: Array = (
		Array(order_value)
		if order_value is PackedFloat64Array
		else (order_value as Array if order_value is Array else [])
	)
	if hist.size() != HIST_DIM or order_z.size() != ORDER_DIM:
		return {}
	return {"stepHist": hist, "stepOrderZ": order_z}


## 用余弦相似度比较五类步骤的组成，任一零向量返回零。
static func composition_similarity(hist_a: Array, hist_b: Array) -> float:
	var dot: float = 0.0
	var norm_a: float = 0.0
	var norm_b: float = 0.0
	for i: int in range(HIST_DIM):
		var a: float = float(hist_a[i])
		var b: float = float(hist_b[i])
		dot += a * b
		norm_a += a * a
		norm_b += b * b
	if norm_a <= 0.0 or norm_b <= 0.0:
		return 0.0
	return dot / (sqrt(norm_a) * sqrt(norm_b))


## 根据标准化顺序向量的平均点积，把相关程度映射到相似度。
static func order_similarity(z_a: Array, z_b: Array) -> float:
	var dot: float = 0.0
	for i: int in range(ORDER_DIM):
		dot += float(z_a[i]) * float(z_b[i])
	var rho: float = dot / float(ORDER_DIM)
	return (1.0 + rho) / 2.0


## 将步骤组成相似度与顺序相似度各取一半。
static func final_similarity(vec_a: Dictionary, vec_b: Dictionary) -> float:
	var f: float = composition_similarity(vec_a["stepHist"], vec_b["stepHist"])
	var g: float = order_similarity(vec_a["stepOrderZ"], vec_b["stepOrderZ"])
	return 0.5 * f + 0.5 * g


## 有效特征的综合相似度达到阈值，才视为同风格题目。
static func is_same_style(vec_a: Dictionary, vec_b: Dictionary) -> bool:
	if vec_a.is_empty() or vec_b.is_empty():
		return false
	return final_similarity(vec_a, vec_b) >= SAME_STYLE_THRESHOLD


## 加入候选后仅比较同尺寸题目，用并查集统计至少两题的相似组；比较预算不足时放行。
static func creates_excess_groups(
	candidate: Dictionary, window: Array, max_groups: int, budget: Dictionary = {}
) -> bool:
	var candidate_vec: Dictionary = extract_vec(candidate)
	if candidate_vec.is_empty():
		return false

	var items: Array = []
	for record: Variant in window:
		var record_dict: Dictionary = record as Dictionary
		var vec: Dictionary = extract_vec(record_dict)
		if not vec.is_empty():
			vec["size"] = int(record_dict.get("style_size", -1))
			items.append(vec)
	candidate_vec["size"] = (
		int(candidate.get("size", 0)) if int(candidate.get("size", 0)) > 0 else -1
	)
	items.append(candidate_vec)

	var n: int = items.size()
	if n < 2:
		return false

	var parent: Array = []
	for i: int in range(n):
		parent.append(i)
	for i: int in range(n):
		for j: int in range(i + 1, n):
			var size_i: int = int(items[i]["size"])
			var size_j: int = int(items[j]["size"])
			if size_i <= 0 or size_j <= 0 or size_i != size_j:
				continue

			if is_budget_exhausted(budget):
				return false
			budget["comparisons_left"] = int(budget.get("comparisons_left", 0)) - 1
			if is_same_style(items[i], items[j]):
				_union(parent, i, j)

	var group_sizes: Dictionary = {}
	for i: int in range(n):
		var root: int = _find(parent, i)
		group_sizes[root] = int(group_sizes.get(root, 0)) + 1
	var group_count: int = 0
	for size: int in group_sizes.values():
		if size >= 2:
			group_count += 1
	return group_count > max_groups


## 检查剩余比较次数和微秒截止时间，空预算字典表示暂不限制。
static func is_budget_exhausted(budget: Dictionary) -> bool:
	if budget.is_empty():
		return false
	return (
		int(budget.get("comparisons_left", 0)) <= 0
		or Time.get_ticks_usec() >= int(budget.get("deadline_usec", 0))
	)


## 沿父节点查并查集根节点，不进行路径压缩。
static func _find(parent: Array, x: int) -> int:
	while int(parent[x]) != x:
		x = int(parent[x])
	return x


## 把两个相似题目的并查集合并到同一根下。
static func _union(parent: Array, a: int, b: int) -> void:
	var root_a: int = _find(parent, a)
	var root_b: int = _find(parent, b)
	if root_a != root_b:
		parent[root_a] = root_b
