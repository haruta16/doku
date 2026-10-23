## 近期题目去重：优先使用预计算规范形哈希与方向表，缺失或失效时重新计算题号。
class_name PuzzleDeduplicator
extends RefCounted


## 解析题号并查询近期记录，同题出现在不同关号才标记重复。
static func inspect(entry: Dictionary, level_num: int) -> Dictionary:
	var size: int = int(entry.get("_delivery_size", entry.get("size", 0)))
	var regions: Array = entry.get("regionMap", [])
	var puzzle_id: String = resolve_puzzle_id(entry, size, regions)
	var previous: Dictionary = GameState.find_recent_puzzle(puzzle_id)
	var duplicate: bool = not previous.is_empty() and int(previous.get("level", -1)) != level_num
	return {"puzzle_id": puzzle_id, "duplicate": duplicate, "previous": previous}


## 组合预计算题号与实际变换，开发构建还重算核验，数据过期时回退真实结果。
static func resolve_puzzle_id(entry: Dictionary, sz: int, region_map: Array) -> String:
	var hash16: String = str(entry.get("_pid_h", ""))
	var suffixes: Array = entry.get("_pid_s", [])

	if hash16.is_empty() or suffixes.size() != LevelData.TRANSFORM_COUNT:
		return LevelData.compute_puzzle_id(sz, region_map)

	var t: int = _effective_transform(entry)
	if t < 0 or t >= LevelData.TRANSFORM_COUNT:
		push_error("PID_TABLE_BAD_TRANSFORM t=%d sz=%d src=%s" % [t, sz, _source_of(entry)])
		return LevelData.compute_puzzle_id(sz, region_map)

	var composed: String = LevelData.compose_puzzle_id(sz, hash16, int(suffixes[t]))

	if not OS.has_feature("rel"):
		var expect: String = LevelData.compute_puzzle_id(sz, region_map)
		if expect != composed:
			push_error(
				(
					"PID_TABLE_STALE expect=%s table=%s sz=%d t=%d src=%s —— 题库变了但没重跑预计算"
					% [expect, composed, sz, t, _source_of(entry)]
				)
			)
			return expect
	return composed


## LK 改题库已经包含方向变化，按零变换处理；其他来源读取交付变换。
static func _effective_transform(entry: Dictionary) -> int:
	if _source_of(entry) == "lk_mod":
		return 0
	return int(entry.get("_bank_transform", 0))


## 统一取得主线来源标识，缺失时回退普通来源字段。
static func _source_of(entry: Dictionary) -> String:
	return str(entry.get("_bank_source_main", entry.get("_bank_source", "")))


## 输出前后交付与游标历史，压缩连续序列以定位重复题原因。
static func log_duplicate(
	previous: Dictionary, entry: Dictionary, level_num: int, puzzle_id: String
) -> void:
	var size: int = int(entry.get("_delivery_size", entry.get("size", 0)))
	var rank: int = int(entry.get("_delivery_rank", 1))
	var bk: String = "%d_%d" % [size, rank]
	var tier_key: String = entry.get("_bank_tier", "")
	var src: String = entry.get("_bank_source_main", entry.get("_bank_source", ""))

	var src_main: String = entry.get("_bank_source_main", "")

	var raw_from := func(snap: Dictionary) -> Dictionary:
		return {
			"lkmod": snap.get("lkmod_progress", {}).get(bk, {}),
			"main": snap.get("main_bank_progress", {}).get(bk, {}),
			"bank": snap.get("bank_progress", {}).get(bk, null),
		}

	var prev_c: Dictionary = {
		"lv": previous.get("level", -1),
		"v": previous.get("v", "?"),
		"nl": previous.get("nl", -1),
		"bk": bk,
		"src": previous.get("src", "?"),
	}
	prev_c.merge(raw_from.call(previous))
	var curr_c: Dictionary = {
		"lv": level_num,
		"v": UniKitManager.get_version_name(),
		"nl": ABTestManager.normal_level.value(),
		"bk": bk,
		"src": src,
		"idx": entry.get("_bank_idx", 0),
		"lkmod": GameState.get_lkmod_progress(size, rank),
		"main": GameState.get_main_progress(size, rank, tier_key),
		"bank": GameState.get_bank_progress_snapshot().get(bk, null),
	}

	var is_main: bool = src_main in ["regular", "lkstyle", "gc"]
	var has_hist: bool
	if src_main == "lk_mod":
		has_hist = not (prev_c.get("lkmod", {}) as Dictionary).is_empty()
	elif is_main:
		has_hist = not (prev_c.get("main", {}) as Dictionary).is_empty()
	else:
		has_hist = prev_c.get("bank") != null
	if not has_hist:
		push_error(
			(
				"DUPLICATE_PUZZLE pid=%s | PREV=%s | CURR=%s"
				% [
					puzzle_id,
					JSON.stringify(prev_c),
					JSON.stringify(curr_c),
				]
			)
		)
		return
	var hb: Array = []
	var hlk: Array = []
	var hmi: Array = []
	var hslk: Array = []
	var prev_track = null
	for he in GameState.get_recent_puzzles():
		var he_lk: Dictionary = he.get("lkmod_progress", {}).get(bk, {})
		var he_mp: Dictionary = he.get("main_bank_progress", {}).get(bk, {})
		var he_b = he.get("bank_progress", {}).get(bk, null)
		var track
		if src_main == "lk_mod":
			track = he_lk.get("idx", null)
		elif is_main:
			track = he_mp.get("idx", null)
		else:
			track = he_b
		if track == null or track == prev_track:
			continue
		prev_track = track
		hb.append(he_b if he_b != null else -1)
		hlk.append(he_lk.get("idx", -1))
		hmi.append(he_mp.get("idx", -1))
		hslk.append(he_mp.get("since_lk", -1))

	var compress := func(arr: Array) -> String:
		if arr.is_empty():
			return ""
		var parts: PackedStringArray = []
		var run_start: int = 0
		while run_start < arr.size():
			var run_end: int = run_start + 1
			while run_end < arr.size() and int(arr[run_end]) == int(arr[run_end - 1]) + 1:
				run_end += 1
			if run_end - run_start >= 3:
				parts.append("%d-%d" % [arr[run_start], arr[run_end - 1]])
			else:
				for k in range(run_start, run_end):
					parts.append(str(arr[k]))
			run_start = run_end
		return ",".join(parts)
	var hist: Dictionary
	if src_main == "lk_mod":
		hist = {"lk": compress.call(hlk)}
	elif is_main:
		hist = {"mi": compress.call(hmi), "slk": compress.call(hslk)}
	else:
		hist = {"b": compress.call(hb)}
	push_error(
		(
			"DUPLICATE_PUZZLE pid=%s | PREV=%s | CURR=%s | HIST=%s"
			% [
				puzzle_id,
				JSON.stringify(prev_c),
				JSON.stringify(curr_c),
				JSON.stringify(hist),
			]
		)
	)
