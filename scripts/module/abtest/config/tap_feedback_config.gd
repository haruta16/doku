extends AbConfigBase
class_name TapFeedbackConfig









const VALUE_CONTROL: int = 0
const VALUE_PRESS_RELEASE_SPLIT: int = 1
const VALUE_ERROR_START_MARK: int = 2
const VALUE_BOTH: int = 3

func _init() -> void :
    key = "tap_feedback"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_APP_START


func is_press_release_split() -> bool:
    return value() == VALUE_PRESS_RELEASE_SPLIT or value() == VALUE_BOTH



func allows_mark_from_error_start() -> bool:
    return value() == VALUE_ERROR_START_MARK or value() == VALUE_BOTH
