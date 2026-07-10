extends AbConfigBase
class_name RateUsPopUiConfig






const VALUE_OLD_UI: int = 0
const VALUE_NEW_UI: int = 1

func _init() -> void :
    key = "rate_us_pop_ui"
    default_value = VALUE_OLD_UI
    timing = ABTestManager.TIMING_GAME_START



func is_new_ui() -> bool:
    return value() == VALUE_NEW_UI
