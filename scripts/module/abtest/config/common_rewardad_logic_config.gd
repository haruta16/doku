## 实验配置 common_rewardad_logic：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name CommonRewardadLogicConfig

# ---- 分组取值 ----
const VALUE_NO_RESTORE: int = 0 # 不做奖励补发

const VALUE_RESTORE: int = 1 # 允许补发奖励


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "common_rewardad_logic"
	default_value = VALUE_RESTORE
