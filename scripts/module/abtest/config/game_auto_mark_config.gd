extends AbConfigBase
class_name GameAutoMarkConfig













const VALUE_CONTROL: int = 0
const VALUE_AUTO_CROSS: int = 1
const VALUE_DOT_TOGGLE: int = 2
const VALUE_AUTO_CROSS_LV6: int = 3
const VALUE_LOCK_X: int = 4
const VALUE_PROP_AD: int = 5

func _init() -> void :
    key = "game_auto_mark"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_GAME_START


func is_auto_cross_after_cat() -> bool:
    return value() == VALUE_AUTO_CROSS or value() == VALUE_AUTO_CROSS_LV6


func after_cat_enabled_at(level: int) -> bool:
    match value():
        VALUE_AUTO_CROSS:
            return true
        VALUE_AUTO_CROSS_LV6:
            return level <= 6
        _:
            return false


func prefill_auto_cross_enabled_at(level: int) -> bool:
    match value():
        VALUE_AUTO_CROSS:
            return level <= 10
        VALUE_AUTO_CROSS_LV6:
            return level <= 6
        _:
            return false


func is_dot_toggle_mode() -> bool:
    return value() == VALUE_DOT_TOGGLE


func is_dot_toggle_enabled_at(level: int) -> bool:
    return value() == VALUE_DOT_TOGGLE and level > 30

func is_lock_x_mode() -> bool:
    return value() == VALUE_LOCK_X



func is_lock_x_enabled_at(_level: int) -> bool:
    return is_lock_x_mode()

func is_prop_ad_mode() -> bool:
    return value() == VALUE_PROP_AD




func is_prop_ad_active_for_daily() -> bool:
    return is_prop_ad_mode() and GameState.is_daily_auto_mark_enabled_for_today()
