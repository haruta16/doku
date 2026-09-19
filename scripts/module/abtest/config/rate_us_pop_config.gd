# 评分弹窗时机实验（取值是字符串）："0"=第 8 关起弹 "1"=第 15 关起弹 "2"=只在回首页时弹 "3"=第 15 关起且本 session 连赢 5 局才弹
extends AbConfigBase
class_name RateUsPopConfig

# ---- 分组取值（字符串型，走 get_ab_string） ----
const VALUE_GATE_LV8: String = "0" # 第 8 关起即可弹
const VALUE_GATE_LV15: String = "1" # 第 15 关起才弹
const VALUE_HOME_AFTER_WIN: String = "2" # 不在过关时弹，改成回首页时弹
const VALUE_WIN_STREAK_5: String = "3" # 第 15 关起且本 session 连赢 5 局


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "rate_us_pop"
	default_value = VALUE_GATE_LV8 # 默认档：第 8 关起
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 过关时是否该弹评分框；会打一行判定日志（档位/关卡/连胜），档位 2 在这里恒为 false
func is_eligible_at_game_win(lv: int, session_consecutive_wins: int) -> bool:
	var v: String = value()
	print(
		(
			"[rate_us_pop] is_eligible_at_game_win: value()=%s, lv=%d, consecutive_wins=%d"
			% [v, lv, session_consecutive_wins]
		)
	)
	match v:
		VALUE_GATE_LV15:
			return lv >= 15
		VALUE_GATE_LV8:
			return lv >= 8
		VALUE_WIN_STREAK_5:
			return lv >= 15 and session_consecutive_wins >= 5
	return false


# 回首页时是否该弹评分框（仅档位 2 且第 8 关后）
func is_eligible_at_home(lv: int) -> bool:
	return value() == VALUE_HOME_AFTER_WIN and lv >= 8
