## 实验配置 third_rule_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ThirdRuleTextConfig

# ---- 分组取值（即文案变体号） ----
const VALUE_CONTROL: int = 0 # 原文案
const VALUE_VARIANT_A: int = 1 # 改写文案 A
const VALUE_VARIANT_B: int = 2 # 改写文案 B
const VALUE_VARIANT_C: int = 3 # 改写文案 C


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "third_rule_text"
	default_value = VALUE_VARIANT_A
