extends AbConfigBase
class_name IdleGuideConfig

const VALUE_OFF: int = 0
const VALUE_ON: int = 1
const VALUE_STEP_TRIGGER: int = 2


func _init() -> void:
	key = "idle_guide"
	default_value = VALUE_OFF
	timing = ABTestManager.TIMING_GAME_START


func cheat_label() -> String:
	return "idle_guide (0=off 1=idle 2=step)"


func is_idle_guide_enabled() -> bool:
	return value() == VALUE_ON


func is_step_trigger_enabled() -> bool:
	return value() == VALUE_STEP_TRIGGER


func suppresses_tool_hint_at_level1() -> bool:
	return value() != VALUE_OFF
