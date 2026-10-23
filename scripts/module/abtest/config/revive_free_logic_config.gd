## 实验配置 revive_free_logic：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ReviveFreeLogicConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不免费
const VALUE_FIRST_LEVEL_UNLIMITED: int = 1 # 第 1 关不限次数免费复活
const VALUE_FIRST_EVER_ONCE: int = 2 # 只免费一次，用过就永久失效


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "revive_free_logic"
	default_value = VALUE_CONTROL
