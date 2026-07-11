extends AbConfigBase
class_name NoDcConfig

const VALUE_SHOW: int = 0
const VALUE_HIDE: int = 1


func _init() -> void:
	key = "no_dc"
	default_value = VALUE_SHOW
	timing = ABTestManager.TIMING_APP_START


func is_daily_challenge_hidden() -> bool:
	return value() == VALUE_HIDE
