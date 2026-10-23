## 实验配置 barrage_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BarrageFuncConfig

const VALUE_DISABLED: int = 0
const VALUE_SINGLE: int = 1
const VALUE_MULTI: int = 2
const UNLOCK_LEVEL: int = 11


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "barrage_func"
	default_value = VALUE_DISABLED


static func is_enabled_for(group: int) -> bool:
	return group == VALUE_SINGLE or group == VALUE_MULTI


static func is_single_barrage_mode_for(group: int) -> bool:
	return group == VALUE_SINGLE


static func is_multi_barrage_mode_for(group: int) -> bool:
	return group == VALUE_MULTI


static func effective_value_for(group: int, current_level: int) -> int:
	if current_level < UNLOCK_LEVEL:
		return VALUE_DISABLED
	return group if is_enabled_for(group) else VALUE_DISABLED


func effective_value() -> int:
	return effective_value_for(int(value()), GameState.get_current_level())


func is_enabled() -> bool:
	return is_enabled_for(effective_value())


func is_single_barrage_mode() -> bool:
	return is_single_barrage_mode_for(effective_value())


func is_multi_barrage_mode() -> bool:
	return is_multi_barrage_mode_for(effective_value())
