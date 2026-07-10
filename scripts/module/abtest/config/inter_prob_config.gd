extends AbConfigBase
class_name InterProbConfig




















const VALUE_CONTROL: int = 0
const VALUE_PROB_50_AT_3: int = 1
const VALUE_PROB_70_AT_2: int = 2
const VALUE_PROB_80_AT_1: int = 3

func _init() -> void :
    key = "inter_prob"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_GAME_START


func is_enabled() -> bool:
    return value() != VALUE_CONTROL



func get_threshold() -> int:
    match value():
        VALUE_PROB_50_AT_3: return 3
        VALUE_PROB_70_AT_2: return 2
        VALUE_PROB_80_AT_1: return 1
        _: return 0


func get_show_percent() -> int:
    match value():
        VALUE_PROB_50_AT_3: return 50
        VALUE_PROB_70_AT_2: return 70
        VALUE_PROB_80_AT_1: return 80
        _: return 100
