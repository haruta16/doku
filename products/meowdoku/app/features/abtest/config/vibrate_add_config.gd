## 实验配置 vibrate_add：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name VibrateAddConfig

const VALUE_KEEP: int = 0
const VALUE_ADD: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "vibrate_add"
	default_value = VALUE_KEEP


func is_enabled() -> bool:
	return value() == VALUE_ADD
