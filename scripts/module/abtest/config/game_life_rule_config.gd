## 实验配置 game_life_rule：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GameLifeRuleConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 关闭补命
const VALUE_PLUS_ONE: int = 1 # 允许对局内补命


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "game_life_rule"
	default_value = VALUE_OFF
