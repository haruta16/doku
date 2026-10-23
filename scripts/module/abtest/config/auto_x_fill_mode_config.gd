## 实验配置 auto_x_fill_mode：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name AutoXFillModeConfig

const VALUE_OFF: int = 0
const VALUE_INSTANT: int = 1
const VALUE_SEQUENTIAL: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "auto_x_fill_mode"
	default_value = VALUE_OFF


func is_enabled() -> bool:
	return int(value()) != VALUE_OFF


func is_instant() -> bool:
	return int(value()) == VALUE_INSTANT
