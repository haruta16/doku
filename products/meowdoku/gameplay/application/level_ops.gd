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
