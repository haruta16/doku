extends AbConfigBase
class_name DdaRankConfig








const VALUE_CONTROL: int = 0
const VALUE_RETRY_ONCE: int = 1
const VALUE_TOOL_REVIVE: int = 2
const VALUE_ANY_ACTION: int = 3

func _init() -> void :
    key = "dda_rank"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_GAME_START_NORMAL


func is_retry_once_demote() -> bool:
    return value() == VALUE_RETRY_ONCE


func is_tool_revive_demote() -> bool:
    return value() == VALUE_TOOL_REVIVE


func is_any_action_demote() -> bool:
    return value() == VALUE_ANY_ACTION
