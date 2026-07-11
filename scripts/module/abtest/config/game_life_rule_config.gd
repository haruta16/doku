extends AbConfigBase
class_name GameLifeRuleConfig

const VALUE_OFF: int = 0
const VALUE_PLUS_ONE: int = 1


func _init() -> void:
	key = "game_life_rule"
	default_value = VALUE_OFF
	timing = ABTestManager.TIMING_APP_START


func is_life_plus_enabled() -> bool:
	return value() == VALUE_PLUS_ONE
