## 实验配置 daily_streak：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DailyStreakConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不显示打卡
const VALUE_BASIC: int = 1 # 基础打卡，带奖励
const VALUE_CHALLENGE_ONLY: int = 2 # 只统计每日挑战局（带奖励）
const VALUE_NO_REWARD: int = 3 # 打卡但不发奖励
const VALUE_NO_LIT: int = 4 # 发奖励但跳过「首次点亮」那一屏
const VALUE_ENTRY: int = 6
const VALUE_ENTRY_REORDER: int = 7


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "daily_streak"
	default_value = VALUE_BASIC


func has_play_entry() -> bool:
	var v: int = value()
	return v == VALUE_ENTRY or v == VALUE_ENTRY_REORDER


func is_settle_reorder() -> bool:
	return value() == VALUE_ENTRY_REORDER
