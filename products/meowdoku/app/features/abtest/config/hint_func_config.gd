## 实验配置 hint_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HintFuncConfig

const VALUE_CONTROL: int = 0
const VALUE_COLOR_EXCLUDE: int = 1
const VALUE_REVERSE_SET_LOCKING: int = 2
const VALUE_BOTH: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "hint_func"
	default_value = VALUE_CONTROL


func has_color_exclude() -> bool:
	var v: int = value()
	return v == VALUE_COLOR_EXCLUDE or v == VALUE_BOTH


func has_reverse_set_locking() -> bool:
	var v: int = value()
	return v == VALUE_REVERSE_SET_LOCKING or v == VALUE_BOTH
