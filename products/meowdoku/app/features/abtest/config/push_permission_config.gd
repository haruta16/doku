## 实验配置 push_permission：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PushPermissionConfig

const VALUE_CONTROL: int = 0
const VALUE_3DAY_PROGRESS: int = 1
const VALUE_SESSION_STREAK: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "push_permission"
	default_value = VALUE_CONTROL
