# 设置页语言切换入口实验：0=隐藏 1=显示语言切换项
extends AbConfigBase
class_name SettingsLanguageConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 隐藏语言切换
const VALUE_SHOW: int = 1 # 显示语言切换


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "settings_language"
	default_value = VALUE_HIDE # 默认档：隐藏
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否显示语言切换入口（仅非对局页生效）
func is_language_switch_enabled() -> bool:
	return value() == VALUE_SHOW
