extends AbConfigBase
class_name GuideFeedbackConfig

const VALUE_CURRENT: int = 0
const VALUE_CHECK: int = 1
const VALUE_IQ: int = 2


func _init() -> void:
	key = "guide_feedback"
	default_value = VALUE_CURRENT
	timing = ABTestManager.TIMING_APP_START


func is_check_guide() -> bool:
	return value() == VALUE_CHECK


func is_iq_guide() -> bool:
	return value() == VALUE_IQ
