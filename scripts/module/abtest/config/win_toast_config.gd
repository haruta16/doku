extends AbConfigBase
class_name WinToastConfig

const VALUE_CONTROL: int = 0
const VALUE_P5: int = 1
const VALUE_P10: int = 2
const VALUE_P20: int = 3


func _init() -> void:
	key = "win_toast"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START


func is_enabled() -> bool:
	return value() != VALUE_CONTROL


func covers_tier(tier: int) -> bool:
	if tier < 0:
		return false
	return value() >= maxi(1, tier)
