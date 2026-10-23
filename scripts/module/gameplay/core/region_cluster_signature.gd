## 区域簇同构检测：提取三个相邻区域的联合轮廓，归一化旋转与镜像后过滤近期相似形状。
class_name RegionClusterSignature
extends RefCounted

const ISO_CLUSTER_SIZE: int = 3

const ISO_TOLERANCE_CELLS: int = 5

const MAX_CLUSTERS_PER_LEVEL: int = 60

static var _stat_compute_calls: int = 0
static var _stat_compute_usec: int = 0
static var _stat_match_calls: int = 0
static var _stat_match_usec: int = 0
static var _stat_match_hits: int = 0


## 清零签名计算、匹配次数和微秒耗时统计。
static func reset_stats() -> void:
	_stat_compute_calls = 0
	_stat_compute_usec = 0
	_stat_match_calls = 0
	_stat_match_usec = 0
	_stat_match_hits = 0


## 返回当前性能与命中统计快照，供选题调试读取。
static func get_stats() -> Dictionary:
	return {
		"compute_calls": _stat_compute_calls,
		"compute_usec": _stat_compute_usec,
		"match_calls": _stat_match_calls,
		"match_usec": _stat_match_usec,
		"match_hits": _stat_match_hits,
	}


## 对行列坐标施加八种旋转或镜像，后续再统一平移到原点。
static func _apply_point_transform(p: Vector2i, t: int) -> Vector2i:
	var r: int = p.x
	var c: int = p.y
	match t:
		0:
			return Vector2i(r, c)
		1:
			return Vector2i(c, -r)
		2:
			return Vector2i(-r, -c)
		3:
			return Vector2i(-c, r)
		4:
			return Vector2i(r, -c)
		5:
			return Vector2i(-r, c)
		6:
			return Vector2i(c, r)
		7:
			return Vector2i(-c, -r)
		_:
			return p


## 枚举八种对称变换并平移、排序，取字典序最小的形状作为规范表示。
static func _canonical_form(cells: Array[Vector2i]) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for t: int in range(8):
		var transformed: Array[Vector2i] = []
		for p: Vector2i in cells:
			transformed.append(_apply_point_transform(p, t))
		var min_r: int = transformed[0].x
		var min_c: int = transformed[0].y
		for p: Vector2i in transformed:
			min_r = mini(min_r, p.x)
			min_c = mini(min_c, p.y)
		var normalized: Array[Vector2i] = []
		for p: Vector2i in transformed:
			normalized.append(Vector2i(p.x - min_r, p.y - min_c))
		normalized.sort()
		if best.is_empty() or normalized < best:
			best = normalized
	return best


## 把规范坐标序列转为字符串键，供形状去重。
static func _form_key(form: Array[Vector2i]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p: Vector2i in form:
		parts.append("%d,%d" % [p.x, p.y])
	return ";".join(parts)


## 按区域收集格子，并从上下左右共享边建立区域邻接关系。
static func _build_adjacency(region_map: Array, sz: int) -> Dictionary:
	var cells_by_region: Dictionary = {}
	var adj: Dictionary = {}
	for r: int in range(sz):
		var row: Array = region_map[r]
		for c: int in range(sz):
			var rid: int = int(row[c])
			if not cells_by_region.has(rid):
				cells_by_region[rid] = [] as Array[Vector2i]
				adj[rid] = {}
			(cells_by_region[rid] as Array).append(Vector2i(r, c))
	for r: int in range(sz):
		var row: Array = region_map[r]
		var next_row: Array = region_map[r + 1] if r + 1 < sz else []
		for c: int in range(sz):
			var rid: int = int(row[c])
			if c + 1 < sz:
				var rid_right: int = int(row[c + 1])
				if rid_right != rid:
					(adj[rid] as Dictionary)[rid_right] = true
					(adj[rid_right] as Dictionary)[rid] = true
			if r + 1 < sz:
				var rid_down: int = int(next_row[c])
				if rid_down != rid:
					(adj[rid] as Dictionary)[rid_down] = true
					(adj[rid_down] as Dictionary)[rid] = true
	return {"cells": cells_by_region, "adj": adj}


## 把已排序区域编号连接成键，避免同一连通子集重复展开。
static func _subset_key(sub: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for x: int in sub:
		parts.append(str(x))
	return ",".join(parts)


## 从各区域出发枚举指定规模的连通区域集合，达到数量上限就停止。
static func _connected_subsets(adj: Dictionary, k: int, max_count: int) -> Array:
	var results: Array = []
	var seen: Dictionary = {}
	var ids: Array = adj.keys()
	ids.sort()
	for start_id: int in ids:
		if results.size() >= max_count:
			break
		_expand_subset(adj, [start_id], k, max_count, seen, results)
	return results


## 递归向当前集合的邻接边界扩展，原地写入去重表和结果数组。
static func _expand_subset(
	adj: Dictionary, sub: Array, k: int, max_count: int, seen: Dictionary, results: Array
) -> void:
	if results.size() >= max_count:
		return
	var key: String = _subset_key(sub)
	if seen.has(key):
		return
	seen[key] = true
	if sub.size() == k:
		results.append(sub.duplicate())
		return
	var subset_set: Dictionary = {}
	for x: int in sub:
		subset_set[x] = true
	var frontier: Dictionary = {}
	for x: int in sub:
		var neighbors: Dictionary = adj.get(x, {})
		for y: int in neighbors.keys():
			if not subset_set.has(y):
				frontier[y] = true
	for y: int in frontier.keys():
		if results.size() >= max_count:
			return
		var ns: Array = sub.duplicate()
		ns.append(y)
		ns.sort()
		_expand_subset(adj, ns, k, max_count, seen, results)


## 计算区域簇签名并累加调用次数与微秒耗时。
static func compute_signatures(region_map: Array, sz: int, min_cluster_size: int = 0) -> Array:
	var t0: int = Time.get_ticks_usec()
	var result: Array = _compute_signatures_impl(region_map, sz, min_cluster_size)
	_stat_compute_calls += 1
	_stat_compute_usec += Time.get_ticks_usec() - t0
	return result


## 枚举三区域连通簇，过滤过小簇，再按规范形状去重。
static func _compute_signatures_impl(region_map: Array, sz: int, min_cluster_size: int) -> Array:
	if sz <= 0 or region_map.size() != sz:
		return []
	var built: Dictionary = _build_adjacency(region_map, sz)
	var cells_by_region: Dictionary = built["cells"]
	var adj: Dictionary = built["adj"]
	if adj.size() < ISO_CLUSTER_SIZE:
		return []
	var subsets: Array = _connected_subsets(adj, ISO_CLUSTER_SIZE, MAX_CLUSTERS_PER_LEVEL)
	var seen_forms: Dictionary = {}
	var result: Array = []
	for subset: Array in subsets:
		var cells: Array[Vector2i] = []
		for rid: int in subset:
			for p: Vector2i in cells_by_region[rid] as Array:
				cells.append(p)
		if cells.size() < min_cluster_size:
			continue
		var canon: Array[Vector2i] = _canonical_form(cells)
		var form_key: String = _form_key(canon)
		if seen_forms.has(form_key):
			continue
		seen_forms[form_key] = true
		result.append(canon)
	return result


## 把坐标数组转成集合字典，加速形状交集判断。
static func _to_point_set(a: Array) -> Dictionary:
	var set_a: Dictionary = {}
	for p: Vector2i in a:
		set_a[p] = true
	return set_a


## 统计两个形状不共有的格子总数，作为容差比较依据。
static func _symmetric_diff_count_with_set(set_a: Dictionary, a_size: int, b: Array) -> int:
	var shared: int = 0
	for p: Vector2i in b:
		if set_a.has(p):
			shared += 1
	return (a_size - shared) + (b.size() - shared)


## 在给定格子容差内搜索相近规范形状，并累计匹配耗时及命中数。
static func has_isomorphic_match(
	signatures: Array, window_signatures: Array, tolerance: int
) -> bool:
	var t0: int = Time.get_ticks_usec()
	var matched: bool = false
	for sig: Array in signatures:
		var sig_size: int = sig.size()
		var set_a: Dictionary = _to_point_set(sig)
		for window_sig: Array in window_signatures:
			if absi(sig_size - window_sig.size()) > tolerance:
				continue
			if _symmetric_diff_count_with_set(set_a, sig_size, window_sig) <= tolerance:
				matched = true
				break
		if matched:
			break
	_stat_match_calls += 1
	_stat_match_usec += Time.get_ticks_usec() - t0
	if matched:
		_stat_match_hits += 1
	return matched


## 返回第一个符合形状容差的历史组编号，没有匹配返回 -1。
static func find_isomorphic_match_group(
	signatures: Array, window_signatures: Array, window_group_ids: Array, tolerance: int
) -> int:
	for sig: Array in signatures:
		var set_a: Dictionary = _to_point_set(sig)
		var sig_size: int = sig.size()
		for i: int in range(window_signatures.size()):
			var window_sig: Array = window_signatures[i]
			if absi(sig_size - window_sig.size()) > tolerance:
				continue
			if _symmetric_diff_count_with_set(set_a, sig_size, window_sig) <= tolerance:
				return int(window_group_ids[i])
	return -1
