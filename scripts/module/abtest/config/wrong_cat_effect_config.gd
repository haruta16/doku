extends AbConfigBase
class_name WrongCatEffectConfig

const VALUE_CONTROL: int = 0
const VALUE_NO_SHAKE: int = 1
const VALUE_LOW_WRONG_VOLUME: int = 2
const VALUE_NO_RED_FILL: int = 3
const VALUE_LOW_FAIL_VOLUME: int = 4
const VALUE_ALL_REDUCED: int = 5


func _init() -> void:
	key = "wrong_cat_effect"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START


func should_skip_shake() -> bool:
	return value() == VALUE_NO_SHAKE or value() == VALUE_ALL_REDUCED


func should_lower_wrong_volume() -> bool:
	return value() == VALUE_LOW_WRONG_VOLUME or value() == VALUE_ALL_REDUCED


func should_skip_red_fill() -> bool:
	return value() == VALUE_NO_RED_FILL or value() == VALUE_ALL_REDUCED


func should_lower_fail_volume() -> bool:
	return value() == VALUE_LOW_FAIL_VOLUME or value() == VALUE_ALL_REDUCED
