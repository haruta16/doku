extends AbConfigBase
class_name AutoCompleteConfig

const VALUE_OFF: int = 0
const VALUE_ON: int = 1
const VALUE_LAST_CAT_ONLY: int = 2


func _init() -> void:
	key = "auto_complete"
	default_value = VALUE_OFF
	timing = ABTestManager.TIMING_GAME_START


func is_enabled() -> bool:
	return value() != VALUE_OFF


func should_auto_mark_crosses() -> bool:
	return value() == VALUE_ON
