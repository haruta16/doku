# 连续打卡实验：0=对照组（不显示打卡） 1=基础版（打卡+第 7 天宝箱） 2=只统计挑战局 3=打卡但不发奖励 4=发奖励但跳过「首次点亮」那一屏
extends AbConfigBase
class_name DailyStreakConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不显示打卡
const VALUE_BASIC: int = 1 # 基础打卡，带奖励
const VALUE_CHALLENGE_ONLY: int = 2 # 只统计每日挑战局（带奖励）
const VALUE_NO_REWARD: int = 3 # 打卡但不发奖励
const VALUE_NO_LIT: int = 4 # 发奖励但跳过「首次点亮」那一屏


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "daily_streak"
	default_value = VALUE_CONTROL # 默认档：不显示打卡
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否启用打卡功能（非对照组）
func is_enabled() -> bool:
	return value() != VALUE_CONTROL


# 是否只统计每日挑战局（仅挑战组）
func is_challenge_only() -> bool:
	return value() == VALUE_CHALLENGE_ONLY


# 是否发第 7 天宝箱（档位 1/2/4，档位 3 不发）
func has_reward() -> bool:
	var v: int = value()
	return v == VALUE_BASIC or v == VALUE_CHALLENGE_ONLY or v == VALUE_NO_LIT


# 是否跳过「首次点亮」那一屏（档位 4）
func is_skip_lit() -> bool:
	return value() == VALUE_NO_LIT
