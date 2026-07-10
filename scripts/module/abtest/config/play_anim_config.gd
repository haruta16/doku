extends AbConfigBase
class_name PlayAnimConfig








const VALUE_CONTROL: int = 0
const VALUE_DISABLED: int = 1

func _init() -> void :
    key = "play_anim"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_APP_START


func is_idle_anim_enabled() -> bool:
    return value() == VALUE_CONTROL
