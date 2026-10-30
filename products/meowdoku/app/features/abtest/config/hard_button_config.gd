## 实验配置 hard_button：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HardButtonConfig

const VALUE_DEFAULT: int = 0
const VALUE_STARS_FIRE: int = 1
const VALUE_YELLOW_FIRE: int = 2
const VALUE_RED1: int = 3
const VALUE_RED2: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "hard_button"
	default_value = VALUE_DEFAULT


func effect_variant() -> int:
	return value()
