# 失败页文案实验：0=对照组（原文案） 1=换成进度鼓励文案 2=鼓励文案并突出复活入口
extends AbConfigBase
class_name FailTextConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用原文案
const VALUE_PROGRESS_TEXT: int = 1 # 换成进度鼓励文案
const VALUE_REVIVE_PROMOTE: int = 2 # 鼓励文案 + 突出复活按钮


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "fail_text"
	default_value = VALUE_CONTROL # 默认档：原文案
	timing = ABTestManager.TIMING_GAME_END # 染色时机：本局失败结算时


# 是否显示鼓励文案（档位 >=1）
func should_show_encourage() -> bool:
	return value() >= VALUE_PROGRESS_TEXT


# 是否突出复活入口（档位 2）
func should_show_revive_promote() -> bool:
	return value() == VALUE_REVIVE_PROMOTE
