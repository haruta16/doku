## 实验配置 prop_position：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PropPositionConfig

const VALUE_LOCATE_FIRST: int = 0

const VALUE_HINT_FIRST: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "prop_position"
	default_value = VALUE_LOCATE_FIRST


func is_hint_first() -> bool:
	return value() == VALUE_HINT_FIRST
