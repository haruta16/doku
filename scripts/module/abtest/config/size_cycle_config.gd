extends AbConfigBase
class_name SizeCycleConfig











const VALUE_CONTROL: int = 2
const VALUE_CYCLE_V3_A: int = 3
const VALUE_CYCLE_V3_B: int = 4
const VALUE_CYCLE_V3_C: int = 5
const VALUE_CYCLE_V3_D: int = 6
const VALUE_CYCLE_V3_E: int = 7
const VALUE_CYCLE_V3_F: int = 8

func _init() -> void :
    key = "size_cycle"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_GAME_START_NORMAL


func is_cycle_enabled() -> bool:
    return value() != VALUE_CONTROL
