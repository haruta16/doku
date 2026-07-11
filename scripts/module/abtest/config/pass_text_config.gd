extends AbConfigBase
class_name PassTextConfig

const VALUE_CONTROL: int = 0
const VALUE_BEAT_PERCENT: int = 1
const VALUE_V2: int = 2


func _init() -> void:
	key = "pass_text"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START


func should_show_beat_percent() -> bool:
	return value() == VALUE_BEAT_PERCENT
