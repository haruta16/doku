## 为 Elo 选题提供单格区域补充题与高潮题的排序、顺序读取和进度提交。
class_name EloAuxProvider
extends RefCounted

static var _single_region_cache: Dictionary = {}
static var _climax_cache: Dictionary = {}
static var _single_region_order_cache: Dictionary = {}
static var _climax_order_cache: Dictionary = {}


## 缓存单格区域题的 Elo 排序，保留原始题号以便接受后提交进度。
static func get_single_region_order(sz: int, rank: int) -> Array:
	var key: String = "%d_%d" % [sz, rank]
	if not _single_region_order_cache.has(key):
		_single_region_order_cache[key] = _build_order(
			_single_region_bucket(sz, rank), "elo_aux_single_region", 0
		)
	return _single_region_order_cache[key]


## 按高潮题当前变换构造 Elo 排序；八种变换耗尽时返回空序列。
static func get_climax_order(sz: int, rank: int) -> Array:
	var prog: Dictionary = GameState.get_elo_aux_climax_progress(sz, rank)
	var transform: int = int(prog.get("t_pos", 0))
	if transform >= LevelData.TRANSFORM_COUNT:
		return []
	var key: String = "%d_%d_%d" % [sz, rank, transform]
	if not _climax_order_cache.has(key):
		_climax_order_cache[key] = _build_order(
			_climax_bucket(sz, rank), "elo_aux_climax", transform
		)
	return _climax_order_cache[key]


## 逐个归并已排序来源，形成统一的 Elo 候选序列。
static func combined_order(orders: Array) -> Array:
	var result: Array = []
	for order: Array in orders:
		result = _merge_orders(result, order)
	return result


## 按 Elo 升序归并两个序列，同分时按 pid 排序。
static func _merge_orders(left: Array, right: Array) -> Array:
	var result: Array = []
	var li: int = 0
	var ri: int = 0
	while li < left.size() and ri < right.size():
		var l: Dictionary = left[li]
		var r: Dictionary = right[ri]
		if l["elo"] < r["elo"] or (l["elo"] == r["elo"] and l["pid"] <= r["pid"]):
			result.append(l)
			li += 1
		else:
			result.append(r)
			ri += 1
	while li < left.size():
		result.append(left[li])
		li += 1
	while ri < right.size():
		result.append(right[ri])
		ri += 1
	return result


## 根据已交付 entry 的来源和原始索引推进对应游标，高潮题到桶末还会切换变换。
static func commit_entry(entry: Dictionary, sz: int, rank: int) -> void:
	var src: String = str(entry.get("_bank_source_main", ""))
	var idx: int = int(entry.get("_bank_idx", 0))
	if src == "elo_aux_single_region":
		var progress: Dictionary = GameState.get_elo_aux_single_region_progress(sz, rank)
		GameState.commit_elo_aux_single_region_delivery(
			sz, rank, {"idx": maxi(int(progress.get("idx", 0)), idx)}
		)
	elif src == "elo_aux_climax":
		var bucket_size: int = _climax_bucket(sz, rank).size()
		var transform: int = int(entry.get("_bank_transform", 0))
		var progress: Dictionary = GameState.get_elo_aux_climax_progress(sz, rank)
		var next_idx: int = maxi(int(progress.get("idx", 0)), idx)
		var next_transform: int = maxi(int(progress.get("t_pos", 0)), transform)
		if next_idx >= bucket_size:
			next_idx = 0
			next_transform = mini(next_transform + 1, LevelData.TRANSFORM_COUNT)
		(
			GameState
			. commit_elo_aux_climax_delivery(
				sz,
				rank,
				{
					"idx": next_idx,
					"t_pos": next_transform,
				}
			)
		)


## 仅收录带 eloRating 的题，附上来源、原始索引和变换，再按 Elo 与 pid 排序。
static func _build_order(bucket: Array, source: String, transform: int) -> Array:
	var order: Array = []
	for i: int in bucket.size():
		var original: Dictionary = bucket[i] as Dictionary
		if not original.has("eloRating"):
			continue
		var pid: String = str(original.get("_pid_h", ""))
		if pid.is_empty():
			pid = (
				"%s:%d:%d:%d"
				% [
					source,
					int(original.get("size", 0)),
					int(original.get("r", original.get("rank", 0))),
					i
				]
			)
		(
			order
			. append(
				{
					"elo": float(original["eloRating"]),
					"pid": pid,
					"ref": original,
					"source": source,
					"idx": i,
					"transform": transform,
					"tier": "",
				}
			)
		)
	order.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if left["elo"] != right["elo"]:
				return left["elo"] < right["elo"]
			return left["pid"] < right["pid"]
	)
	return order


## 按单格区域来源的当前进度加 skip 读取候选，并返回待提交进度。
static func next_single_region(sz: int, rank: int, skip: int = 0) -> Dictionary:
	var bucket: Array = _single_region_bucket(sz, rank)
	if bucket.is_empty():
		return {}
	var prog: Dictionary = GameState.get_elo_aux_single_region_progress(sz, rank)
	var idx: int = int(prog.get("idx", 0)) + skip
	if idx >= bucket.size():
		return {}
	var entry: Dictionary = BankData.materialize_entry(bucket[idx] as Dictionary, true)
	entry["_bank_source"] = "elo_aux_single_region"
	entry["_bank_source_main"] = "elo_aux_single_region"
	entry["_bank_idx"] = idx + 1
	entry["_bank_transform"] = 0
	entry["_bank_rank"] = rank
	entry["_bank_tier"] = ""
	return {"entry": entry, "sz": sz, "rank": rank, "new_progress": {"idx": idx + 1}}


## 按高潮题进度读取候选；跨桶时切换变换，八轮结束后无候选。
static func next_climax(sz: int, rank: int, skip: int = 0) -> Dictionary:
	var bucket: Array = _climax_bucket(sz, rank)
	if bucket.is_empty():
		return {}
	var prog: Dictionary = GameState.get_elo_aux_climax_progress(sz, rank)
	var raw_idx: int = int(prog.get("idx", 0))
	var t_pos: int = int(prog.get("t_pos", 0))
	var offset: int = skip
	var idx: int = raw_idx + offset
	while idx >= bucket.size():
		idx -= bucket.size()
		t_pos += 1
	if t_pos >= LevelData.TRANSFORM_COUNT:
		return {}
	var entry: Dictionary = BankData.materialize_entry(bucket[idx] as Dictionary, true)
	var transform: int = t_pos
	if transform > 0:
		entry = _apply_transform(entry, transform)
	entry["_bank_source"] = "elo_aux_climax"
	entry["_bank_source_main"] = "elo_aux_climax"
	entry["_bank_idx"] = idx + 1
	entry["_bank_transform"] = transform
	entry["_bank_rank"] = rank
	entry["_bank_tier"] = ""
	return {
		"entry": entry,
		"sz": sz,
		"rank": rank,
		"new_progress": {"idx": idx + 1 if idx + 1 < bucket.size() else 0, "t_pos": t_pos}
	}


## 根据候选携带的来源，将待提交进度写入对应 GameState 字段。
static func commit(picked: Dictionary) -> void:
	if picked.is_empty():
		return
	var src: String = str(picked.get("entry", {}).get("_bank_source_main", ""))
	if src == "elo_aux_single_region":
		GameState.commit_elo_aux_single_region_delivery(
			int(picked.get("sz", 0)), int(picked.get("rank", 0)), picked.get("new_progress", {})
		)
	elif src == "elo_aux_climax":
		GameState.commit_elo_aux_climax_delivery(
			int(picked.get("sz", 0)), int(picked.get("rank", 0)), picked.get("new_progress", {})
		)


## 按尺寸和难度缓存单格区域补充题桶。
static func _single_region_bucket(sz: int, rank: int) -> Array:
	var key: String = "%d_%d" % [sz, rank]
	if _single_region_cache.has(key):
		return _single_region_cache[key]
	var result: Array = []
	for e: Variant in BankData.get_single_region_levels():
		var entry: Dictionary = e as Dictionary
		if int(entry.get("size", 0)) != sz:
			continue
		if int(entry.get("r", 0)) != rank:
			continue
		result.append(entry)
	_single_region_cache[key] = result
	return result


## 按尺寸和难度缓存高潮题桶。
static func _climax_bucket(sz: int, rank: int) -> Array:
	var key: String = "%d_%d" % [sz, rank]
	if _climax_cache.has(key):
		return _climax_cache[key]
	var result: Array = []
	for e: Variant in BankData.get_climax_filter_levels():
		var entry: Dictionary = e as Dictionary
		if int(entry.get("size", 0)) != sz:
			continue
		if int(entry.get("r", 0)) != rank:
			continue
		result.append(entry)
	_climax_cache[key] = result
	return result


## 原地同时变换区域图和答案。
static func _apply_transform(entry: Dictionary, transform: int) -> Dictionary:
	var rm: Array = []
	for row: Variant in entry.get("regionMap", []):
		var int_row: Array = []
		for v: Variant in row as Array:
			int_row.append(int(v))
		rm.append(int_row)
	var sol: Array = []
	for v: Variant in entry.get("solution", []):
		sol.append(int(v))
	var sz: int = rm.size()
	if sz == 0:
		return entry
	var result: Array = LevelData.apply_transform(rm, sol, sz, transform)
	entry["regionMap"] = result[0]
	entry["solution"] = result[1]
	return entry
