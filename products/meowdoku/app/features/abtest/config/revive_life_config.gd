## 实验配置 revive_life：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ReviveLifeConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，只补 1 条命
const VALUE_GROUP_1: int = 1 # 补 3 条命
const VALUE_GROUP_2: int = 2 # 补 3 条命，按钮用两行文案
const VALUE_GROUP_3: int = 3 # 补 3 条命，按钮用备用文案


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "revive_life"
	default_value = VALUE_GROUP_3
