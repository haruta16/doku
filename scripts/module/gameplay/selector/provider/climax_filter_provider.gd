## 按尺寸、难度与单格区域数筛选高潮题，依次遍历题桶及八种对称变换。
class_name ClimaxFilterProvider
extends RefCounted

static var _bucket_cache: Dictionary = {}


## 以保存的索引加 skip 试取候选；跨过桶末时推进变换，返回 entry 和待提交进度。
static func next_entry(sz: int, rank: int, single_count: int, skip: int = 0) -> Dictionary:
	var bucket: Array = _bucket_entries(sz, rank, single_count)
	if bucket.is_empty():
		return {}
	var prog: Dictionary = GameState.get_climax_filter_progress(sz, rank, single_count)
	var idx: int = int(prog.get("idx", 0)) + skip
	var t_pos: int = int(prog.get("t_pos", 0))
	while idx >= bucket.size():
		idx -= bucket.size()
		t_pos += 1
	if t_pos >= LevelData.TRANSFORM_COUNT:
		return {}

	var entry: Dictionary = BankData.materialize_entry(bucket[idx] as Dictionary, true)
	if t_pos > 0:
		entry = _apply_entry_transform(entry, t_pos)
	entry["_bank_source"] = "climax_filter"
	entry["_bank_source_main"] = "climax_filter"
	entry["_bank_idx"] = idx + 1
	entry["_bank_transform"] = t_pos
	entry["_bank_rank"] = rank
	entry["_bank_tier"] = ""
	entry["_bank_single_count"] = single_count

	return {
		"entry": entry,
		"sz": sz,
		"rank": rank,
		"single_count": single_count,
		"new_progress": {"idx": idx + 1, "t_pos": t_pos},
	}


## 只在候选被接受后，把高潮题游标写入 GameState。
static func commit(picked: Dictionary) -> void:
	if picked.is_empty():
		return
	GameState.commit_climax_filter_delivery(
		int(picked.get("sz", 0)),
		int(picked.get("rank", 0)),
		int(picked.get("single_count", 0)),
		picked.get("new_progress", {})
	)


## 缓存满足尺寸、难度和单格区域数约束的高潮题子集。
static func _bucket_entries(sz: int, rank: int, single_count: int) -> Array:
	var key: String = "%d_%d_%d" % [sz, rank, single_count]
	if _bucket_cache.has(key):
		return _bucket_cache[key]
	var result: Array = []
	for e: Variant in BankData.get_climax_filter_levels():
		var entry: Dictionary = e as Dictionary
		if int(entry.get("size", 0)) != sz:
			continue
		if int(entry.get("r", 0)) != rank:
			continue
		if int(entry.get("singleCount", -1)) != single_count:
			continue
		result.append(entry)
	_bucket_cache[key] = result
	return result


## 原地同步变换题目的区域图与答案。
static func _apply_entry_transform(entry: Dictionary, transform: int) -> Dictionary:
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
