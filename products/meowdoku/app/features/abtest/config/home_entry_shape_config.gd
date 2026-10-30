## 实验配置 home_entry_shape：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HomeEntryShapeConfig

const VALUE_CURRENT_WIDGET: int = 0
const VALUE_BTN_TWO_WIDGET: int = 1
const VALUE_ICON_TOP: int = 2
const VALUE_LOGO_SWAP: int = 3
const VALUE_RANK_SIDE: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "home_entry_shape"
	default_value = VALUE_CURRENT_WIDGET


func get_shape() -> int:
	return int(value())


func is_enabled() -> bool:
	return value() != VALUE_CURRENT_WIDGET


func has_daily_btn() -> bool:
	return value() in [VALUE_BTN_TWO_WIDGET, VALUE_LOGO_SWAP, VALUE_RANK_SIDE]


func is_logo_swapped() -> bool:
	return value() == VALUE_LOGO_SWAP
