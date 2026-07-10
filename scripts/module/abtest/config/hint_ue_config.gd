extends AbConfigBase
class_name HintUeConfig







const VALUE_CONTROL: int = 0
const VALUE_NEW_FLOW: int = 1

const VALUE_CLOSE_BTN: int = 2

func _init() -> void :
    key = "hint_ue"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_HINT_USE


func is_new_hint_flow() -> bool:
    return value() == VALUE_NEW_FLOW


func is_close_btn_flow() -> bool:
    return value() == VALUE_CLOSE_BTN


func is_any_new_flow() -> bool:
    return value() == VALUE_NEW_FLOW or value() == VALUE_CLOSE_BTN
