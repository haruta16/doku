## 实验配置 normal_level_10：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NormalLevel10Config

# ---- 分组取值 ----
const VALUE_SP44: int = 0 # 第 10 关用 sp44
const VALUE_SP57: int = 1 # 第 10 关换成 sp57


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "normal_level_10"
	default_value = VALUE_SP44
