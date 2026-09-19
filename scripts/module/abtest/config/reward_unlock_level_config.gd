# 激励广告门槛实验：打到第几关之后才要求看广告，低于该关卡直接发奖励
extends AbConfigBase
class_name RewardUnlockLevelConfig

# ---- 门槛值 ----
const DEFAULT_UNLOCK_LEVEL: int = 0 # 默认门槛 0：所有关卡都要求看广告


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "reward_unlock_level"
	default_value = DEFAULT_UNLOCK_LEVEL # 默认档：全关卡都要求
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 该关卡是否仍要求看广告（低于门槛时调用方直接发奖励）
func is_reward_required_at(level: int) -> bool:
	return level >= value()
