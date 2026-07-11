extends AbConfigBase
class_name PropHighlightConfig

const VALUE_CONTROL: int = 0
const VALUE_LOCATE_ONCE: int = 1
const VALUE_HINT_ONCE: int = 2
const VALUE_NONE: int = 3
const VALUE_CONTROL_REPEATABLE: int = 4


func _init() -> void:
	key = "prop_highlight"
	default_value = VALUE_CONTROL

	timing = ABTestManager.TIMING_GAME_START


func target_prop() -> String:
	match value():
		VALUE_LOCATE_ONCE:
			return "locate"
		VALUE_HINT_ONCE:
			return "hint"
		VALUE_NONE:
			return "none"
		VALUE_CONTROL_REPEATABLE:
			return "random"
		_:
			return "control"


func is_once_per_lifetime() -> bool:
	return value() == VALUE_LOCATE_ONCE or value() == VALUE_HINT_ONCE


func is_repeatable() -> bool:
	return value() == VALUE_CONTROL_REPEATABLE
