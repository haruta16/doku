extends AbConfigBase
class_name NormalStartToastConfig







const VALUE_HIDE: int = 0
const VALUE_TEXT_VARIANT_A: int = 1
const VALUE_TEXT_VARIANT_B: int = 2


const VALUE_GROUP1: int = 3
const VALUE_GROUP2: int = 4
const VALUE_GROUP3: int = 5
const VALUE_GROUP4: int = 6

func _init() -> void :
    key = "normal_start_toast"
    default_value = VALUE_HIDE
    timing = ABTestManager.TIMING_GAME_START_NORMAL_11




func should_show_toast() -> bool:
    return value() != VALUE_HIDE





func should_show_iq_text() -> bool:
    return value() >= VALUE_TEXT_VARIANT_B



func get_variant_card() -> String:
    match value():
        VALUE_GROUP2:
            return "Card4"
        VALUE_GROUP3:
            return "Card5"
        VALUE_GROUP4:
            return "Card6"
        _:
            return "Card2"
