extends AbConfigBase
class_name IconCrashConfig







const VALUE_HEART_CRASH: int = 0
const VALUE_NO_CRASH: int = 1
const VALUE_FISH_CRASH: int = 2

func _init() -> void :
    key = "icon_crash"
    default_value = VALUE_HEART_CRASH
    timing = ABTestManager.TIMING_GAME_START

func is_no_crash() -> bool:
    return value() == VALUE_NO_CRASH

func is_fish_crash() -> bool:
    return value() == VALUE_FISH_CRASH
