## 实验配置 no_dc：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NoDcConfig

# ---- 分组取值 ----
const VALUE_SHOW: int = 0 # 显示每日挑战入口
const VALUE_HIDE: int = 1 # 隐藏每日挑战入口


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "no_dc"
	default_value = VALUE_SHOW
