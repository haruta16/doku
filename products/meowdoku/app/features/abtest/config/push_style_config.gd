## 实验配置 push_style：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PushStyleConfig

const VALUE_CONTROL: int = 0
const VALUE_NORMAL_PUSH: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "push_style"
	default_value = VALUE_CONTROL


func is_normal_push() -> bool:
	return value() == VALUE_NORMAL_PUSH
