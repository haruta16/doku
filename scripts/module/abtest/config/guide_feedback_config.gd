# 新手引导反馈实验：0=现有引导 1=打勾式引导 2=IQ 式引导
extends AbConfigBase
class_name GuideFeedbackConfig

# ---- 分组取值 ----
const VALUE_CURRENT: int = 0 # 现有引导
const VALUE_CHECK: int = 1 # 打勾式引导
const VALUE_IQ: int = 2 # IQ 式引导


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "guide_feedback"
	default_value = VALUE_CURRENT # 默认档：现有引导
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否用打勾式引导
func is_check_guide() -> bool:
	return value() == VALUE_CHECK


# 是否用 IQ 式引导
func is_iq_guide() -> bool:
	return value() == VALUE_IQ
