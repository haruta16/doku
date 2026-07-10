extends AbConfigBase
class_name FunctionClearConfig






const VALUE_HIDE: int = 0
const VALUE_SHOW: int = 1

func _init() -> void :
    key = "function_clear"
    default_value = VALUE_HIDE
    timing = ABTestManager.TIMING_GAME_START


func should_show_clear_btn() -> bool:
    return value() == VALUE_SHOW
