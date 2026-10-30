## 实验配置 revive_countdown：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ReviveCountdownConfig

const VALUE_CONTROL: int = 0
const VALUE_GROUP_1: int = 1
const VALUE_GROUP_2: int = 2
const VALUE_GROUP_3: int = 3
const VALUE_GROUP_4: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "revive_countdown"
	default_value = VALUE_CONTROL
