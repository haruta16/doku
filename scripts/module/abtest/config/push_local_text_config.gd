extends AbConfigBase
class_name PushLocalTextConfig






const VALUE_LEGACY: int = 0
const VALUE_NEW_POOL: int = 1

func _init() -> void :
    key = "push_local_text"
    default_value = VALUE_LEGACY
    timing = ABTestManager.TIMING_APP_START

func is_new_pool() -> bool:
    return value() == VALUE_NEW_POOL
