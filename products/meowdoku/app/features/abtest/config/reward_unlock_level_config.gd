## 实验配置 reward_unlock_level：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RewardUnlockLevelConfig

# ---- 门槛值 ----
const DEFAULT_UNLOCK_LEVEL: int = 0 # 默认门槛 0：所有关卡都要求看广告


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "reward_unlock_level"
	default_value = DEFAULT_UNLOCK_LEVEL


## 该关卡是否仍要求看广告（低于门槛时调用方直接发奖励）
func is_reward_required_at(level: int) -> bool:
	return level >= value()
