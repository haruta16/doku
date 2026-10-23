## 实验配置 auto_complete：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name AutoCompleteConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 关闭自动完成
const VALUE_ON: int = 1 # 开启，自动完成时连叉一起补
const VALUE_LAST_CAT_ONLY: int = 2 # 开启，但只补猫、不补叉


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "auto_complete"
	default_value = VALUE_OFF
