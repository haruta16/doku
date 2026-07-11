extends AbConfigBase
class_name AutoScreenOffConfig

const VALUE_ALWAYS_ON: int = 0
const VALUE_AUTO_OFF: int = 1


func _init() -> void:
	key = "auto_screen_off"
	default_value = VALUE_ALWAYS_ON
	timing = ABTestManager.TIMING_NO_ACTION_270


func is_auto_off() -> bool:
	return value() == VALUE_AUTO_OFF
