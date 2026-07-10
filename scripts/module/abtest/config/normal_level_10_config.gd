extends AbConfigBase
class_name NormalLevel10Config






const VALUE_SP44: int = 0
const VALUE_SP57: int = 1

func _init() -> void :
    key = "normal_level_10"
    default_value = VALUE_SP44
    timing = ABTestManager.TIMING_GAME_START_NORMAL


func is_sp57_at_level10() -> bool:
    return value() == VALUE_SP57
