## 实验配置 auto_screen_off：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name AutoScreenOffConfig

# ---- 分组取值 ----
const VALUE_ALWAYS_ON: int = 0 # 一直保持屏幕常亮
const VALUE_AUTO_OFF: int = 1 # 挂机后放开 keep_on，交给系统超时息屏


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "auto_screen_off"
	default_value = VALUE_ALWAYS_ON


## 挂机后是否允许系统息屏
func is_auto_off() -> bool:
	return value() == VALUE_AUTO_OFF
