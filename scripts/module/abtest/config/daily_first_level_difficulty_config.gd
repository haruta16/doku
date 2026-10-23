## 实验配置 daily_first_level_difficulty：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DailyFirstLevelDifficultyConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，首关保持原难度
const VALUE_REDUCE_ONE: int = 1 # 首关难度降一档


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "daily_first_level_difficulty"
	default_value = VALUE_REDUCE_ONE
