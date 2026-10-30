## 实验配置 pre_cat：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PreCatConfig

const VALUE_OFF: int = 0
const VALUE_ALWAYS: int = 1
const VALUE_HALF: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "pre_cat"
	default_value = VALUE_ALWAYS
