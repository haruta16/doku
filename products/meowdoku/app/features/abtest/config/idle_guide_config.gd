## 实验配置 idle_guide：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name IdleGuideConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 关闭挂机引导
const VALUE_ON: int = 1 # 空闲超时触发引导
const VALUE_STEP_TRIGGER: int = 2 # 按步数触发引导


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "idle_guide"
	default_value = VALUE_OFF
