## 按尺寸和难度缓存单格区域补充题；候选读取与进度提交分开，便于筛选失败时继续尝试。
class_name SingleRegionSuppProvider
extends RefCounted

static var _bucket_cache: Dictionary = {}


## 只接受目标单格区域数为 1 的请求；按当前进度加 skip 取题，并返回待提交的新进度。
static func next_entry(sz: int, rank: int, target_single_count: int, skip: int = 0) -> Dictionary:
	if target_single_count != 1:
		return {}
	var bucket: Array = _bucket_entries(sz, rank)
	if bucket.is_empty():
		return {}
	var prog: Dictionary = GameState.get_single_region_supp_progress(sz, rank)
	var idx: int = int(prog.get("idx", 0)) + skip
	if idx >= bucket.size():
		return {}
	var entry: Dictionary = BankData.materialize_entry(bucket[idx] as Dictionary, true)
	entry["_bank_source"] = "single_region_supp"
	entry["_bank_source_main"] = "single_region_supp"
	entry["_bank_idx"] = idx + 1
	entry["_bank_transform"] = 0
	entry["_bank_rank"] = rank
	entry["_bank_tier"] = ""
	return {"entry": entry, "sz": sz, "rank": rank, "new_progress": {"idx": idx + 1}}


## 把最终选中的补充题进度交给 GameState 保存。
static func commit(picked: Dictionary) -> void:
	if picked.is_empty():
		return
	GameState.commit_single_region_supp_delivery(
		int(picked.get("sz", 0)), int(picked.get("rank", 0)), picked.get("new_progress", {})
	)


## 按尺寸和难度过滤补充题库并缓存，后续请求复用同一桶。
static func _bucket_entries(sz: int, rank: int) -> Array:
	var key: String = "%d_%d" % [sz, rank]
	if _bucket_cache.has(key):
		return _bucket_cache[key]
	var result: Array = []
	for e: Variant in BankData.get_single_region_levels():
		var entry: Dictionary = e as Dictionary
		if int(entry.get("size", 0)) != sz:
			continue
		if int(entry.get("r", 0)) != rank:
			continue
		result.append(entry)
	_bucket_cache[key] = result
	return result
