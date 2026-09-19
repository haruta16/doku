# 每日首局降档实验：0=对照组 1=当天第一次对局难度降一档（特殊关/难关不降，机会照样消耗，见 GameState.evaluate_daily_first_easy）
extends AbConfigBase
class_name DailyFirstLevelDifficultyConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，首关保持原难度
const VALUE_REDUCE_ONE: int = 1 # 首关难度降一档


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "daily_first_level_difficulty"
	default_value = VALUE_CONTROL # 默认档：不降难度
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否启用每日首局降档（调用方据此评估并推进每日机会）
func is_enabled() -> bool:
	return value() == VALUE_REDUCE_ONE
