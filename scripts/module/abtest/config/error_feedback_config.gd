extends AbConfigBase
class_name ErrorFeedbackConfig







const VALUE_ALL: int = 0
const VALUE_CONFLICT_ONLY: int = 1
const VALUE_NONE: int = 2

func _init() -> void :
    key = "error_feedback"
    default_value = VALUE_ALL
    timing = ABTestManager.TIMING_GAME_START


func only_conflicting_cats_react() -> bool:
    return value() == VALUE_CONFLICT_ONLY


func no_cats_react() -> bool:
    return value() == VALUE_NONE
