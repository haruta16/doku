## 实验配置 error_feedback：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ErrorFeedbackConfig

# ---- 分组取值 ----
const VALUE_ALL: int = 0 # 所有猫都给反馈
const VALUE_CONFLICT_ONLY: int = 1 # 只让冲突的猫反应
const VALUE_NONE: int = 2 # 猫都不反应


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "error_feedback"
	default_value = VALUE_ALL
