## 每日挑战残局快照：保存盘面、计时和得分状态，并在恢复前验证日期、会话和数据完整性。
class_name DailyEndgameSnapshot
extends RefCounted

const VERSION: int = 1

const LEVEL_CONFIG_KEYS: Array[String] = [
	"size",
	"rank",
	"tier",
	"seed",
	"daily_index",
	"daily_transform",
	"bank_source",
	"bank_idx",
	"bank_transform",
	"rating",
]

const _REQUIRED_KEYS: Array[String] = [
	"version",
	"date",
	"session_id",
	"size",
	"level_config",
	"regions",
	"solution",
	"placed_cats",
	"marks",
	"errors",
	"lives",
	"mistake_count",
	"score",
	"combo",
	"max_combo",
	"se_count",
	"se_last_step",
	"elapsed_sec",
]

const _NUMBER_KEYS: Array[String] = [
	"version",
	"size",
	"lives",
	"mistake_count",
	"score",
	"combo",
	"max_combo",
	"se_count",
	"se_last_step",
	"elapsed_sec",
]

const _CELL_LIST_KEYS: Array[String] = ["placed_cats", "marks", "errors"]

const _LEVEL_NUMBER_KEYS: Array[String] = [
	"rank",
	"seed",
	"daily_index",
	"daily_transform",
	"bank_idx",
	"bank_transform",
	"rating",
]
const _LEVEL_TEXT_KEYS: Array[String] = ["tier", "bank_source"]

const _TOAST_NUMBER_KEYS: Array[String] = ["last_cat_sec", "last_cat_step", "player_cat_count"]


## 按白名单保存关卡配置，并复制盘面、分数、计时与提示状态，避免后续操作修改快照。
static func build(
	date: String,
	session_id: String,
	level_config: Dictionary,
	regions: Array,
	solution_1d: Array,
	cells: Dictionary,
	lives: int,
	mistake_count: int,
	score_state: Dictionary,
	elapsed_sec: int,
	toast_state: Dictionary
) -> Dictionary:
	var kept_config: Dictionary = {}
	for key: String in LEVEL_CONFIG_KEYS:
		if level_config.has(key):
			kept_config[key] = level_config[key]
	var placed_cats: Array = cells.get("placed_cats", [])
	var marks: Array = cells.get("marks", [])
	var errors: Array = cells.get("errors", [])
	var cat_toast: Dictionary = toast_state.get("cat_toast", {})
	return {
		"version": VERSION,
		"date": date,
		"session_id": session_id,
		"size": int(level_config.get("size", 0)),
		"level_config": kept_config,
		"regions": regions.duplicate(true),
		"solution": solution_1d.duplicate(),
		"placed_cats": placed_cats.duplicate(true),
		"marks": marks.duplicate(true),
		"errors": errors.duplicate(true),
		"lives": lives,
		"mistake_count": mistake_count,
		"score": int(score_state.get("score", 0)),
		"combo": int(score_state.get("combo", 0)),
		"max_combo": int(score_state.get("max_combo", 0)),
		"se_count": int(score_state.get("se_count", 0)),
		"se_last_step": int(score_state.get("se_last_step", 0)),
		"elapsed_sec": elapsed_sec,
		"operable_sec": float(toast_state.get("operable_sec", 0.0)),
		"cat_toast": cat_toast.duplicate(true),
		"cat_progress_rotate_start": int(toast_state.get("cat_progress_rotate_start", -1)),
	}


## 同时检查实验、日期、有效进度和可选同会话限制，不恢复强制新开局。
static func should_restore(
	snapshot: Dictionary,
	group_enabled: bool,
	require_same_session: bool,
	forced_fresh: bool,
	started_today: bool,
	today: String,
	session_id: String,
	life_cap: int
) -> bool:
	if not group_enabled or forced_fresh or not started_today:
		return false
	if not _is_well_formed(snapshot, life_cap):
		return false
	if not has_progress(snapshot):
		return false
	if str(snapshot["date"]) != today:
		return false
	if require_same_session:
		var saved_session: String = str(snapshot["session_id"])
		if saved_session.is_empty() or saved_session != session_id:
			return false
	return true


static func has_progress(snapshot: Dictionary) -> bool:
	for key: String in _CELL_LIST_KEYS:
		var cells: Variant = snapshot.get(key, [])
		if typeof(cells) == TYPE_ARRAY and not (cells as Array).is_empty():
			return true
	var mistakes: Variant = snapshot.get("mistake_count", 0)
	if _is_number(mistakes) and int(mistakes) > 0:
		return true
	var score: Variant = snapshot.get("score", 0)
	return _is_number(score) and int(score) > 0


## 从快照提取游戏页需要的分数和提示恢复参数，嵌套提示数据另作深拷贝。
static func restore_params(snapshot: Dictionary) -> Dictionary:
	var cat_toast: Dictionary = {}
	var raw_toast: Variant = snapshot.get("cat_toast", {})
	if typeof(raw_toast) == TYPE_DICTIONARY:
		cat_toast = (raw_toast as Dictionary).duplicate(true)
	return {
		"restore_score": int(snapshot.get("score", 0)),
		"restore_combo": int(snapshot.get("combo", 0)),
		"restore_max_combo": int(snapshot.get("max_combo", 0)),
		"restore_se_count": int(snapshot.get("se_count", 0)),
		"restore_se_last_step": int(snapshot.get("se_last_step", 0)),
		"restore_operable_sec": float(snapshot.get("operable_sec", 0.0)),
		"restore_cat_toast": cat_toast,
		"restore_cat_progress_rotate": int(snapshot.get("cat_progress_rotate_start", -1)),
	}


static func solution_grid(solution_1d: Array, size: int) -> Array:
	var grid: Array = []
	for row_index in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(false)
		if row_index < solution_1d.size():
			var col: int = int(solution_1d[row_index])
			if col >= 0 and col < size:
				row[col] = true
		grid.append(row)
	return grid


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## 验证版本、数值、生命、区域、解和坐标范围，拒绝已完成或结构损坏的残局。
static func _is_well_formed(snapshot: Dictionary, life_cap: int) -> bool:
	if snapshot.is_empty():
		return false
	for key: String in _REQUIRED_KEYS:
		if not snapshot.has(key):
			return false
	for key: String in _NUMBER_KEYS:
		if not _is_number(snapshot[key]):
			return false
	if int(snapshot["version"]) != VERSION:
		return false
	if typeof(snapshot["date"]) != TYPE_STRING or typeof(snapshot["session_id"]) != TYPE_STRING:
		return false
	if typeof(snapshot["level_config"]) != TYPE_DICTIONARY:
		return false
	var size: int = int(snapshot["size"])
	if size <= 0:
		return false
	var lives: int = int(snapshot["lives"])
	if lives < 1 or lives > life_cap:
		return false
	if int(snapshot["elapsed_sec"]) < 0:
		return false
	if not _grid_matches_size(snapshot["regions"], size):
		return false
	var solution: Variant = snapshot["solution"]
	if typeof(solution) != TYPE_ARRAY or (solution as Array).size() != size:
		return false
	if not _puzzle_is_valid(snapshot["regions"] as Array, solution as Array, size):
		return false
	if not _level_config_matches(snapshot["level_config"] as Dictionary, size):
		return false
	if not _toast_state_is_valid(snapshot):
		return false
	for key: String in _CELL_LIST_KEYS:
		if not _cells_in_range(snapshot[key], size):
			return false
	var placed_cats: Array = snapshot["placed_cats"]
	return placed_cats.size() < size


static func _puzzle_is_valid(regions: Array, solution: Array, size: int) -> bool:
	var int_regions: Array = []
	for region_row: Array in regions:
		var int_row: Array = []
		for region_id: Variant in region_row:
			if not _is_number(region_id):
				return false
			int_row.append(int(region_id))
		int_regions.append(int_row)
	var int_solution: Array = []
	for column: Variant in solution:
		if not _is_number(column):
			return false
		int_solution.append(int(column))
	return QueendokuCore.validate_solution_entry(
		{"regionMap": int_regions, "solution": int_solution}, size
	)


static func _level_config_matches(config: Dictionary, size: int) -> bool:
	if not config.has("size") or not _is_number(config["size"]) or int(config["size"]) != size:
		return false
	for key: String in _LEVEL_NUMBER_KEYS:
		if config.has(key) and not _is_number(config[key]):
			return false
	for key: String in _LEVEL_TEXT_KEYS:
		if config.has(key) and typeof(config[key]) != TYPE_STRING:
			return false
	return true


static func _toast_state_is_valid(snapshot: Dictionary) -> bool:
	if snapshot.has("operable_sec") and not _is_number(snapshot["operable_sec"]):
		return false
	if (
		snapshot.has("cat_progress_rotate_start")
		and not _is_number(snapshot["cat_progress_rotate_start"])
	):
		return false
	if not snapshot.has("cat_toast"):
		return true
	if typeof(snapshot["cat_toast"]) != TYPE_DICTIONARY:
		return false
	var toast: Dictionary = snapshot["cat_toast"]
	for key: String in _TOAST_NUMBER_KEYS:
		if toast.has(key) and not _is_number(toast[key]):
			return false
	if toast.has("level_key") and typeof(toast["level_key"]) != TYPE_STRING:
		return false
	if toast.has("fired"):
		if typeof(toast["fired"]) != TYPE_ARRAY:
			return false
		var fired: Array = toast["fired"]
		for scene: Variant in fired:
			if not _is_number(scene):
				return false
	return true


static func _grid_matches_size(grid: Variant, size: int) -> bool:
	if typeof(grid) != TYPE_ARRAY:
		return false
	var rows: Array = grid
	if rows.size() != size:
		return false
	for row_value: Variant in rows:
		if typeof(row_value) != TYPE_ARRAY or (row_value as Array).size() != size:
			return false
	return true


static func _cells_in_range(cells: Variant, size: int) -> bool:
	if typeof(cells) != TYPE_ARRAY:
		return false
	var entries: Array = cells
	for entry: Variant in entries:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 2:
			return false
		var pair: Array = entry
		if not _is_number(pair[0]) or not _is_number(pair[1]):
			return false
		var row: int = int(pair[0])
		var col: int = int(pair[1])
		if row < 0 or row >= size or col < 0 or col >= size:
			return false
	return true
