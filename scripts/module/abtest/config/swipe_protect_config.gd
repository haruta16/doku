extends AbConfigBase
class_name SwipeProtectConfig












const VALUE_CONTROL: int = 0
const VALUE_HOTZONE_40: int = 1
const VALUE_HOTZONE_10: int = 2
const VALUE_HOTZONE_RAISED: int = 3

func _init() -> void :
    key = "swipe_protect"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_GAME_START


func is_enabled() -> bool:
    return value() in [VALUE_HOTZONE_40, VALUE_HOTZONE_10, VALUE_HOTZONE_RAISED]


func min_size() -> int:
    return 7 if value() == VALUE_HOTZONE_RAISED else 0


func tolerance_pct() -> float:
    return 0.1 if value() == VALUE_HOTZONE_10 else 0.4


func threshold_for(n: int) -> int:
    if value() == VALUE_HOTZONE_RAISED:
        return ceili(n * 0.6)
    return 4
