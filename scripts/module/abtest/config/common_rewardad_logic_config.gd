# 激励广告奖励补发实验：0=发奖超时就算了 1=发奖超时时把奖励记进待补发列表，回首页再补弹
extends AbConfigBase
class_name CommonRewardadLogicConfig

# ---- 分组取值 ----
const VALUE_NO_RESTORE: int = 0 # 不做奖励补发
const VALUE_RESTORE: int = 1 # 允许补发奖励


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "common_rewardad_logic"
	default_value = VALUE_NO_RESTORE # 默认档：不补发
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 发奖超时时是否记账补发（开启后会给 GameState 写待补发记录）
func should_grant_reward_restore() -> bool:
	return value() == VALUE_RESTORE
