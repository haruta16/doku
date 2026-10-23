## 轮询六类 sp_tt 形状题；每类只用允许的旋转或镜像，提交时同时保存题内进度和下一类别。
class_name SpTtProvider
extends RefCounted

const CATEGORY_COUNT: int = 6
const _CAN_MIRROR: Dictionary = {1: false, 2: false, 3: false, 4: true, 5: true, 6: true}
const _CAN_ROTATE: Dictionary = {1: false, 2: true, 3: true, 4: true, 5: true, 6: true}


## 从当前类别开始轮询六类，跳过指定题号，返回首个可用候选及其待提交进度。
static func next_entry(sz: int, rank: int, skip_ids: Array = []) -> Dictionary:
	var start_cat: int = GameState.get_sp_tt_category_cursor()
	for i: int in range(CATEGORY_COUNT):
		var cat: int = ((start_cat - 1 + i) % CATEGORY_COUNT) + 1
		var picked: Dictionary = _try_category(cat, sz, rank, skip_ids)
		if not picked.is_empty():
			picked["sz"] = sz
			picked["rank"] = rank
			return picked
	return {}


## 提交选中类别的进度，并让下一次选题从后续类别开始。
static func commit(picked: Dictionary, level_num: int) -> void:
	if picked.is_empty():
		return
	var cat: int = int(picked.get("category", 0))
	if cat <= 0:
		return
	var next_cursor: int = cat % CATEGORY_COUNT + 1
	GameState.commit_sp_tt_delivery(
		level_num,
		cat,
		int(picked.get("sz", 0)),
		int(picked.get("rank", 0)),
		picked.get("new_progress", {}),
		next_cursor
	)


## 在类别题桶内推进索引，桶末切换变换；所有允许变换耗尽后返回空字典。
static func _try_category(cat: int, sz: int, rank: int, skip_ids: Array = []) -> Dictionary:
	var bucket: Array = _bucket_entries(cat, sz, rank)
	if bucket.is_empty():
		return {}
	var allowed: Array = _allowed_transforms(cat)
	var prog: Dictionary = GameState.get_sp_tt_progress(cat, sz, rank)
	var idx: int = int(prog.get("idx", 0))
	var t_pos: int = int(prog.get("t_pos", 0))
	while true:
		if idx >= bucket.size():
			idx = 0
			t_pos += 1
		if t_pos >= allowed.size():
			return {}
		if not skip_ids.has(int((bucket[idx] as Dictionary).get("id", -1))):
			break
		idx += 1

	var entry: Dictionary = BankData.materialize_entry(bucket[idx] as Dictionary, true)
	var transform: int = allowed[t_pos]
	if transform > 0:
		entry = _apply_entry_transform(entry, transform)

	entry["_bank_source"] = "sp_tt%d" % cat
	entry["_bank_source_main"] = "sp_tt"
	entry["_bank_idx"] = idx + 1
	entry["_bank_transform"] = transform
	entry["_bank_rank"] = rank
	entry["_bank_tier"] = ""
	entry["_sp_tt_category"] = cat

	return {
		"entry": entry,
		"category": cat,
		"new_progress": {"idx": idx + 1, "t_pos": t_pos},
	}


## 给出类别允许的变换：第一类仅原形，第二、三类只旋转，其余类可用八种对称变换。
static func _allowed_transforms(cat: int) -> Array:
	if _CAN_MIRROR.get(cat, false):
		var all: Array = []
		for t: int in range(LevelData.TRANSFORM_COUNT):
			all.append(t)
		return all
	if _CAN_ROTATE.get(cat, false):
		return [0, 1, 2, 3]
	return [0]


## 向其他选题策略开放当前类别、尺寸和难度的缓存题桶。
static func bucket_entries(cat: int, sz: int, rank: int) -> Array:
	return _bucket_entries(cat, sz, rank)


## 向外提供与顺序选题一致的类别变换集合。
static func allowed_transforms(cat: int) -> Array:
	return _allowed_transforms(cat)


## 原地变换传入 entry 的区域图和答案，并返回同一字典。
static func apply_entry_transform(entry: Dictionary, transform: int) -> Dictionary:
	return _apply_entry_transform(entry, transform)


## 按形状类别、尺寸和难度过滤 sp_tt 题库，结果按组合键缓存。
static func _bucket_entries(cat: int, sz: int, rank: int) -> Array:
	var result: Array = []
	for e: Variant in BankData.get_sp_tt_levels():
		var entry: Dictionary = e as Dictionary
		if int(entry.get("shapeCategory", 0)) != cat:
			continue
		if int(entry.get("size", 0)) != sz:
			continue
		if int(entry.get("r", 0)) != rank:
			continue
		result.append(entry)
	return result


## 同步变换区域图与答案，避免棋盘布局和答案坐标失配。
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
