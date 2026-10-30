## 实验配置 tap_feedback：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name TapFeedbackConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组
const VALUE_PRESS_RELEASE_SPLIT: int = 1 # 按下与抬起分开处理
const VALUE_ERROR_START_MARK: int = 2 # 从错误格起手也允许打叉
const VALUE_BOTH: int = 3 # 两者都启用


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "tap_feedback"
	default_value = VALUE_CONTROL
