# 对局页规则栏位置实验：0=猫（目标）在上，原布局 1=规则栏在上
extends AbConfigBase
class_name GamePageRulesUiConfig

# ---- 分组取值 ----
const VALUE_CAT_ABOVE: int = 0 # 猫在上，保持原布局
const VALUE_RULE_ABOVE: int = 1 # 规则栏换到上方


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "game_page_rules_ui"
	default_value = VALUE_CAT_ABOVE # 默认档：猫在上
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 规则栏是否在上方（同时决定进场动画名）
func is_rule_bar_above() -> bool:
	return value() == VALUE_RULE_ABOVE
