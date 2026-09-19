# 关卡收尾入口：把 GameState 与 Tracker 的多步调用收在一处，供失败页/重开按钮复用
class_name LevelOps
extends RefCounted


# 主线关卡失败确认：清结算快照 → 记一局结束 → 上报埋点，关卡号有效才记失败
static func confirm_level_failed_main(end_params: Dictionary, lv: int) -> void:
	GameState.clear_endgame_snapshot() # 清掉未完成的结算快照
	GameState.on_game_finished() # 计入局数并落盘
	Tracker.track_game_end(end_params) # 上报对局结束埋点
	# 关卡号 > 0 才算真实失败（0 表示没有关卡上下文）
	if lv > 0:
		GameState.on_level_failed(lv)


# 每日关失败确认：不记失败进度，只结束对局并上报
static func confirm_level_failed_daily(end_params: Dictionary) -> void:
	GameState.on_game_finished()
	Tracker.track_game_end(end_params)


# 重开按钮：重置本局统计并累加重开次数
static func on_restart_click() -> void:
	Tracker.on_restart() # 重置回合统计 + restart_count 加一
