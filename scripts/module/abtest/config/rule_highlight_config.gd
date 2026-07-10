extends AbConfigBase
class_name RuleHighlightConfig







const VALUE_CONTROL: int = 0
const VALUE_HIGHLIGHT_VIOLATED: int = 1
const VALUE_HIGHLIGHT_ALL_LEVELS: int = 2

func _init() -> void :
    key = "rule_highlight"
    default_value = VALUE_CONTROL

    timing = ABTestManager.TIMING_GAME_START



func is_highlight_violated() -> bool:
    return value() != VALUE_CONTROL



func is_all_levels() -> bool:
    return value() == VALUE_HIGHLIGHT_ALL_LEVELS
