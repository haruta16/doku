# 清空按钮实验：对局页是否显示「清空」按钮；0=隐藏 1=显示（当前代码里没有调用点，属预留实验）
extends AbConfigBase
class_name FunctionClearConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 不显示清空按钮
const VALUE_SHOW: int = 1 # 显示清空按钮


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "function_clear"
	default_value = VALUE_HIDE # 默认档：隐藏
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否显示清空按钮（当前无调用点）
func should_show_clear_btn() -> bool:
	return value() == VALUE_SHOW
