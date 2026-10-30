## 实验配置 game_page_rules_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GamePageRulesUiConfig

# ---- 分组取值 ----
const VALUE_CAT_ABOVE: int = 0 # 猫在上，保持原布局
const VALUE_RULE_ABOVE: int = 1 # 规则栏换到上方


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "game_page_rules_ui"
	default_value = VALUE_CAT_ABOVE
