## 实验配置 guide_feedback：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GuideFeedbackConfig

# ---- 分组取值 ----
const VALUE_CURRENT: int = 0 # 现有引导
const VALUE_CHECK: int = 1 # 打勾式引导
const VALUE_IQ: int = 2 # IQ 式引导


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "guide_feedback"
	default_value = VALUE_CURRENT
