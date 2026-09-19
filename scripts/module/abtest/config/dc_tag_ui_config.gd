# 每日挑战角标实验：0=对照组（原角标） 1=换成猫爪角标
extends AbConfigBase
class_name DcTagUiConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用原角标
const VALUE_PAW: int = 1 # 用猫爪角标


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "dc_tag_ui"
	default_value = VALUE_CONTROL # 默认档：原角标
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否用猫爪角标
func is_paw_enabled() -> bool:
	return value() == VALUE_PAW
