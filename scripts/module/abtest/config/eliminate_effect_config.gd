# 消除特效实验：叉被消掉时的动画表现；0=原效果 1=叉改成缩小消失 2=去掉消除时的发光
extends AbConfigBase
class_name EliminateEffectConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 沿用原有效果
const VALUE_SHRINK_CROSS: int = 1 # 叉改成缩小消失
const VALUE_NO_GLOW: int = 2 # 去掉消除时的发光


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "eliminate_effect"
	default_value = VALUE_DEFAULT # 默认档：原效果
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 叉是否改成缩小消失
func is_shrink_cross() -> bool:
	return value() == VALUE_SHRINK_CROSS


# 是否去掉发光
func is_remove_glow() -> bool:
	return value() == VALUE_NO_GLOW
