extends AbConfigBase
class_name WarnLifeConfig











const VALUE_HIDE: int = 0
const VALUE_SHOW: int = 1

func _init() -> void :
    key = "warn_life"
    default_value = VALUE_HIDE
    timing = ABTestManager.TIMING_GAME_START


func should_show_life_warning() -> bool:
    return value() == VALUE_SHOW
