## 选题过程的私有工作副本。接口对应旧 GameState 取题方法，但所有写入只落在此副本。
## resolve 可多次预览或重试，实际存档只由 commit_selected 接收最终结果。
class_name DokuSelectionState
extends RefCounted

const PROFILE_FIELDS: Array[String] = [
	"current_level", "current_strategy", "bank_progress", "main_bank_progress", "lkmod_progress",
	"daily_first_easy_date", "recent_puzzles",
]
const RUNTIME_FIELDS: Array[String] = ["is_daily_first_easy_level", "rnr_mod1_exempt", "rnr_g_prev_was_max"]

var profile: Dictionary
var runtime: Dictionary
var daily_available: bool
var today: String


func _init(state: Dictionary) -> void:
	profile = state.get("profile", {}).duplicate(true)
	runtime = state.get("runtime", {}).duplicate(true)
	daily_available = bool(state.get("daily_available", false))
	today = str(state.get("today", ""))


func snapshot() -> Dictionary:
	return {"profile": profile.duplicate(true), "runtime": runtime.duplicate(true), "daily_available": daily_available, "today": today}


func get_current_strategy() -> int:
	return int(profile.get("current_strategy", 1))


func set_current_strategy(strategy: int) -> void:
	profile["current_strategy"] = strategy


func get_bank_index(size: int, rank: int, tier: String = "") -> int:
	return int(profile.get("bank_progress", {}).get(_key(size, rank, tier), 0))


func advance_bank_index(size: int, rank: int, tier: String = "") -> void:
	var progress: Dictionary = profile.get("bank_progress", {})
	var key: String = _key(size, rank, tier)
	progress[key] = int(progress.get(key, 0)) + 1
	profile["bank_progress"] = progress


func get_main_progress(size: int, rank: int, tier: String = "") -> Dictionary:
	var progress: Dictionary = profile.get("main_bank_progress", {})
	return progress.get(_key(size, rank, tier), {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0}).duplicate(true)


func set_main_progress(size: int, rank: int, tier: String, progress: Dictionary) -> void:
	var values: Dictionary = profile.get("main_bank_progress", {})
	values[_key(size, rank, tier)] = progress.duplicate(true)
	profile["main_bank_progress"] = values


func get_lkmod_progress(size: int, rank: int) -> Dictionary:
	return profile.get("lkmod_progress", {}).get(_key(size, rank), {"idx": 0}).duplicate(true)


func set_lkmod_progress(size: int, rank: int, progress: Dictionary) -> void:
	var values: Dictionary = profile.get("lkmod_progress", {})
	values[_key(size, rank)] = progress.duplicate(true)
	profile["lkmod_progress"] = values


func is_daily_first_easy_available() -> bool:
	return daily_available and str(profile.get("daily_first_easy_date", "")) < today


func consume_daily_first_easy_and_mark() -> void:
	consume_daily_first_easy()
	runtime["is_daily_first_easy_level"] = true


func consume_daily_first_easy() -> void:
	daily_available = false
	profile["daily_first_easy_date"] = today


func mark_rnr_mod1_exempt() -> void:
	runtime["rnr_mod1_exempt"] = true


func is_rnr_g_prev_was_max() -> bool:
	return bool(runtime.get("rnr_g_prev_was_max", false))


func set_rnr_g_prev_was_max(value: bool) -> void:
	runtime["rnr_g_prev_was_max"] = value


static func _key(size: int, rank: int, tier: String = "") -> String:
	return "%d_%d%s" % [size, rank, "_H" if tier == "H" else ""]
