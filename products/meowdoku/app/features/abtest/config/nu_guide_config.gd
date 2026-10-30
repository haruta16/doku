## 实验配置 nu_guide：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NuGuideConfig

const VALUE_CURRENT_FLOW: int = 0
const VALUE_SKIPPABLE: int = 1
const VALUE_NEW_FLOW: int = 2
const VALUE_CONFIRM_TRIMMED: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "nu_guide"
	default_value = VALUE_CURRENT_FLOW


func is_skippable() -> bool:
	return value() == VALUE_SKIPPABLE


func is_new_guide_flow() -> bool:
	return value() == VALUE_NEW_FLOW


func is_confirm_step_removed() -> bool:
	return value() == VALUE_CONFIRM_TRIMMED
