## 实验配置 function_clear：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FunctionClearConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 不显示清空按钮
const VALUE_SHOW: int = 1 # 显示清空按钮


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "function_clear"
	default_value = VALUE_HIDE
