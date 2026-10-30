## 实验配置 rule_highlight：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RuleHighlightConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不高亮
const VALUE_HIGHLIGHT_VIOLATED: int = 1 # 违反哪条就高亮哪条
const VALUE_HIGHLIGHT_ALL_LEVELS: int = 2 # 所有关卡都高亮


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rule_highlight"
	default_value = VALUE_CONTROL
