# 过关页文案实验：0=对照组 1=显示「击败了 x% 玩家」 2=第二版文案（策略类按档位选实现）
extends AbConfigBase
class_name PassTextConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组原文案
const VALUE_BEAT_PERCENT: int = 1 # 显示击败百分比
const VALUE_V2: int = 2 # 第二版文案


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "pass_text"
	default_value = VALUE_CONTROL # 默认档：原文案
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否显示击败百分比
func should_show_beat_percent() -> bool:
	return value() == VALUE_BEAT_PERCENT
