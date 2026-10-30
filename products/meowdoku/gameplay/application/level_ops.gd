## 关卡收尾入口：把 GameState 与 Tracker 的多步调用收在一处，供失败页/重开按钮复用
class_name LevelOps
extends RefCounted


## 页面可以离开之前，先确认放弃结算已经完整保存；重复请求不重复埋点。
static func confirm_level_failed_main(end_params: Dictionary, lv: int, attempt_id: String, runtime: Dictionary = {}) -> bool:
	var result: Dictionary = GameState.settle_main_round(attempt_id, lv, "quit", runtime) if lv > 0 else GameState.settle_preview_round(attempt_id, "quit", runtime)
	if not result.get("ok", false):
		return false
	if not result.get("duplicate", false):
		Tracker.track_game_end(end_params)
	return true


static func confirm_level_failed_daily(end_params: Dictionary, attempt_id: String, date: String, runtime: Dictionary = {}) -> bool:
	var result: Dictionary = GameState.settle_daily_round(attempt_id, date, "quit", 0, 0.0, runtime)
	if not result.get("ok", false):
		return false
	if not result.get("duplicate", false):
		Tracker.track_game_end(end_params)
	return true


## 重开按钮：重置本局统计并累加重开次数
static func on_restart_click() -> void:
	Tracker.on_restart() # 重置回合统计 + restart_count 加一

class RecProgress:
	const FINISH: String = "finish"

	const SKIP: String = "skip"


static func _extract_rec_history(
	end_params: Dictionary, progress_state: String = "", pre_cat_positions: Array = []
) -> Dictionary:
	var game_type: String = str(end_params.get("game_type", ""))
	if game_type != Tracker.GameType.NORMAL and game_type != Tracker.GameType.GOLDEN_FISH:
		print("[AlgoLevel] rec_history: skip record, game_type=%s" % game_type)
		return {}
	var recorded_pre_cat_positions: Array = []
	for position: Array in pre_cat_positions:
		recorded_pre_cat_positions.append([int(position[0]), int(position[1])])
	var now: int = int(Time.get_unix_time_from_system())

	var record: Dictionary = {
		"exact_qid": str(end_params.get("qid", "")),
		"level": int(end_params.get("level", 0)),
		"end_ts_s": now,
		"game_type": game_type,
		"result": str(end_params.get("result", "")),
		"duration_seconds": float(end_params.get("time_total", 0)),
		"fail_times": int(end_params.get("gamedie_count", 0)),
		"restart_times": int(end_params.get("restart_count", 0)),
		"hint_used_total": int(end_params.get("hint_used_total", 0)),
		"locate_used_total": int(end_params.get("locate_used_total", 0)),
		"draft_used_total": int(end_params.get("draft_used_total", 0)),
		"mouse_used_total": int(end_params.get("mouse_used_total", 0)),
		"pre_cat_positions": recorded_pre_cat_positions,
	}

	if not progress_state.is_empty():
		record["progress_state"] = progress_state
	print("[AlgoLevel] rec_history: %s" % JSON.stringify(record))
	return record
