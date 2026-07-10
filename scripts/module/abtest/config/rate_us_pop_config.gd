extends AbConfigBase
class_name RateUsPopConfig








const VALUE_GATE_LV8: String = "0"
const VALUE_GATE_LV15: String = "1"
const VALUE_HOME_AFTER_WIN: String = "2"
const VALUE_WIN_STREAK_5: String = "3"

func _init() -> void :
    key = "rate_us_pop"
    default_value = VALUE_GATE_LV8
    timing = ABTestManager.TIMING_GAME_START







func is_eligible_at_game_win(lv: int, session_consecutive_wins: int) -> bool:
    var v: String = value()
    print("[rate_us_pop] is_eligible_at_game_win: value()=%s, lv=%d, consecutive_wins=%d" % [v, lv, session_consecutive_wins])
    match v:
        VALUE_GATE_LV15:
            return lv >= 15
        VALUE_GATE_LV8:
            return lv >= 8
        VALUE_WIN_STREAK_5:
            return lv >= 15 and session_consecutive_wins >= 5
    return false




func is_eligible_at_home(lv: int) -> bool:
    return value() == VALUE_HOME_AFTER_WIN and lv >= 8
