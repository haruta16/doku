# 进度强调实验：0=默认（文字进度的原样式） 1=换成进度条
extends AbConfigBase
class_name ProgressEmphasisConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 沿用文字进度
const VALUE_PROGRESS_BAR: int = 1 # 换成进度条


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "progress_emphasis"
	default_value = VALUE_DEFAULT # 默认档：文字进度
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否用进度条样式
func is_progress_bar() -> bool:
	return value() == VALUE_PROGRESS_BAR
