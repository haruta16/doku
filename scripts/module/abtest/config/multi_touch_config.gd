## 实验配置 multi_touch：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name MultiTouchConfig

const VALUE_SINGLE: int = 0

const VALUE_MULTI: int = 1

const VALUE_SHARED_INPUT: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "multi_touch"
	default_value = VALUE_SINGLE


func is_multi_touch_enabled() -> bool:
	return value() == VALUE_MULTI


func should_use_single_finger_lock() -> bool:
	var touch_value: int = int(value())
	return touch_value != VALUE_MULTI and touch_value != VALUE_SHARED_INPUT
