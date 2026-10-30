## 实验配置 meow_feedback：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name MeowFeedbackConfig

const VALUE_DISABLED: int = 0
const VALUE_EVERY: int = 1
const VALUE_FIRST_ONLY: int = 2
const VALUE_CRESCENDO: int = 3
const VALUE_RANDOM: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "meow_feedback"
	default_value = VALUE_DISABLED
