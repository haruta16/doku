extends AbConfigBase
class_name RuleTextConfig

const VALUE_TEXT: int = 0
const VALUE_THIRD_IMG: int = 1
const VALUE_ALL_IMG: int = 2
const VALUE_ICON_TEXT: int = 3
const VALUE_COLLAPSE_10: int = 4
const VALUE_INFO_POPUP: int = 5
const VALUE_SETTING_ENTRY: int = 6
const VALUE_SINGLE_SWIPE: int = 7


func _init() -> void:
	key = "rule_text"
	default_value = VALUE_TEXT
	timing = ABTestManager.TIMING_GAME_START


func is_third_img() -> bool:
	return value() == VALUE_THIRD_IMG


func is_all_img() -> bool:
	return value() == VALUE_ALL_IMG


func is_icon_text() -> bool:
	return value() == VALUE_ICON_TEXT


func is_collapse_10() -> bool:
	return value() == VALUE_COLLAPSE_10


func is_info_popup() -> bool:
	return value() == VALUE_INFO_POPUP


func is_setting_entry() -> bool:
	return value() == VALUE_SETTING_ENTRY


func is_single_swipe() -> bool:
	return value() == VALUE_SINGLE_SWIPE


func value_i() -> int:
	return int(value())
