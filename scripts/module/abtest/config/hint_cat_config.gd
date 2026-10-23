## 实验配置 hint_cat：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HintCatConfig

const VALUE_BULB: int = 0
const VALUE_BULB_PAW: int = 1
const VALUE_BULB_EAR: int = 2
const VALUE_YARN_BULB: int = 3
const VALUE_BULB_EAR2: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "hint_cat"
	default_value = VALUE_BULB
