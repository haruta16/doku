# 连击鼓励实验：连击时给玩家什么正反馈；0=关 1=固定文案 2=文案+语音 3=分数 4=IQ 分 5=分数+跟手猫 6=女声语音
extends AbConfigBase
class_name ComboEncourageConfig

# ---- 分组取值 ----
const VALUE_DISABLED: int = 0 # 关闭连击鼓励
const VALUE_ENCOURAGE_FIXED: int = 1 # 只出固定鼓励文案
const VALUE_ENCOURAGE_VOICE: int = 2 # 文案 + 语音
const VALUE_ENCOURAGE_SCORE: int = 3 # 额外显示连击得分
const VALUE_ENCOURAGE_IQ: int = 4 # 分数以 IQ 形式展示
const VALUE_ENCOURAGE_FOLLOW: int = 5 # 分数 + 跟着连击位置跑的猫
const VALUE_ENCOURAGE_VOICE_FEMALE: int = 6 # 语音换女声


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "combo_encourage"
	default_value = VALUE_DISABLED # 默认档：关闭
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否启用连击鼓励
func is_enabled() -> bool:
	return value() != VALUE_DISABLED


# 是否带分数展示（档位 3/4/5）
func has_score_display() -> bool:
	var v: int = value()
	return v == VALUE_ENCOURAGE_SCORE or v == VALUE_ENCOURAGE_IQ or v == VALUE_ENCOURAGE_FOLLOW


# 分数是否以 IQ 形式展示（档位 4）
func is_iq_mode() -> bool:
	return value() == VALUE_ENCOURAGE_IQ


# 是否播连击语音（档位 2/6）
func should_play_voice() -> bool:
	var v: int = value()
	return v == VALUE_ENCOURAGE_VOICE or v == VALUE_ENCOURAGE_VOICE_FEMALE


# 语音是否用女声（档位 6）
func is_female_voice() -> bool:
	return value() == VALUE_ENCOURAGE_VOICE_FEMALE


# 是否让猫跟着连击走（档位 5）
func is_follow_cat() -> bool:
	return value() == VALUE_ENCOURAGE_FOLLOW
