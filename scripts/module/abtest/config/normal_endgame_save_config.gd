extends AbConfigBase
class_name NormalEndgameSaveConfig

const VALUE_OFF: int = 0
const VALUE_ON: int = 1


func _init() -> void:
	key = "normal_endgame_save"
	default_value = VALUE_ON
	timing = ABTestManager.TIMING_GAME_START_NORMAL


func is_enabled() -> bool:
	return value() == VALUE_ON
