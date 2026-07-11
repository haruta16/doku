extends AbConfigBase
class_name EliminateEffectConfig

const VALUE_DEFAULT: int = 0
const VALUE_SHRINK_CROSS: int = 1
const VALUE_NO_GLOW: int = 2


func _init() -> void:
	key = "eliminate_effect"
	default_value = VALUE_DEFAULT
	timing = ABTestManager.TIMING_APP_START


func is_shrink_cross() -> bool:
	return value() == VALUE_SHRINK_CROSS


func is_remove_glow() -> bool:
	return value() == VALUE_NO_GLOW
