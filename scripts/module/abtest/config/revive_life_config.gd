extends AbConfigBase
class_name ReviveLifeConfig

const VALUE_CONTROL: int = 0
const VALUE_GROUP_1: int = 1
const VALUE_GROUP_2: int = 2
const VALUE_GROUP_3: int = 3


func _init() -> void:
	key = "revive_life"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START


func get_lives_to_restore() -> int:
	return 1 if value() == VALUE_CONTROL else 3


func is_two_line_button() -> bool:
	return value() == VALUE_GROUP_2


func is_alt_button_text() -> bool:
	return value() == VALUE_GROUP_3
