extends AbConfigBase
class_name GamePageRulesUiConfig

const VALUE_CAT_ABOVE: int = 0
const VALUE_RULE_ABOVE: int = 1


func _init() -> void:
	key = "game_page_rules_ui"
	default_value = VALUE_CAT_ABOVE
	timing = ABTestManager.TIMING_APP_START


func is_rule_bar_above() -> bool:
	return value() == VALUE_RULE_ABOVE
