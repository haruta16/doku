extends AbConfigBase
class_name ReviveFreeLogicConfig









const VALUE_CONTROL: int = 0
const VALUE_FIRST_LEVEL_UNLIMITED: int = 1
const VALUE_FIRST_EVER_ONCE: int = 2

func _init() -> void :
    key = "revive_free_logic"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_APP_START


func should_free_revive() -> bool:
    var v: int = value()
    match v:
        VALUE_FIRST_LEVEL_UNLIMITED:
            return GameState.get_current_level() == 1
        VALUE_FIRST_EVER_ONCE:
            return not GameState.has_used_revive_free()
        _:
            return false


func consume_if_needed() -> void :
    if value() == VALUE_FIRST_EVER_ONCE:
        GameState.mark_revive_free_used()
