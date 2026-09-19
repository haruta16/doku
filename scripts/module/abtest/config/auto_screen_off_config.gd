# 挂机息屏实验：无操作 270 秒后是否放开屏幕常亮；0=一直保持常亮 1=允许系统按自己的超时息屏
extends AbConfigBase
class_name AutoScreenOffConfig

# ---- 分组取值 ----
const VALUE_ALWAYS_ON: int = 0 # 一直保持屏幕常亮
const VALUE_AUTO_OFF: int = 1 # 挂机后放开 keep_on，交给系统超时息屏


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "auto_screen_off"
	default_value = VALUE_ALWAYS_ON # 默认档：保持常亮
	timing = ABTestManager.TIMING_NO_ACTION_270 # 染色时机：挂机 270 秒触发时（由 ScreenManager 调）


# 挂机后是否允许系统息屏
func is_auto_off() -> bool:
	return value() == VALUE_AUTO_OFF
