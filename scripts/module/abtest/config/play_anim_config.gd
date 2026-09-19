# 待机动画实验：0=对照组（保留猫的待机动画） 1=关闭待机动画（省性能/更安静）
extends AbConfigBase
class_name PlayAnimConfig

# ---- 分组取值（数值方向与函数名相反，注意） ----
const VALUE_CONTROL: int = 0 # 保留待机动画
const VALUE_DISABLED: int = 1 # 关闭待机动画


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "play_anim"
	default_value = VALUE_CONTROL # 默认档：保留待机动画
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 待机动画是否启用（只有对照组为真）
func is_idle_anim_enabled() -> bool:
	return value() == VALUE_CONTROL
