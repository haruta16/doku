extends AbConfigBase
class_name ThirdRuleTextConfig

const VALUE_CONTROL: int = 0
const VALUE_VARIANT_A: int = 1
const VALUE_VARIANT_B: int = 2
const VALUE_VARIANT_C: int = 3


func _init() -> void:
	key = "third_rule_text"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_START


func get_rule_text_variant() -> int:
	return value()
