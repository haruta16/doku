# 错猫特效弱化实验：0=对照组 1=不震动 2=错标音效降低 3=不填红 4=失败音效降低 5=以上全部弱化
extends AbConfigBase
class_name WrongCatEffectConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，全部保留
const VALUE_NO_SHAKE: int = 1 # 错标时不震动
const VALUE_LOW_WRONG_VOLUME: int = 2 # 错标音效降低音量
const VALUE_NO_RED_FILL: int = 3 # 错标格不填红
const VALUE_LOW_FAIL_VOLUME: int = 4 # 失败音效降低音量
const VALUE_ALL_REDUCED: int = 5 # 以上全部弱化


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "wrong_cat_effect"
	default_value = VALUE_CONTROL # 默认档：不弱化
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否跳过震动（档位 1/5）
func should_skip_shake() -> bool:
	return value() == VALUE_NO_SHAKE or value() == VALUE_ALL_REDUCED


# 是否降低错标音效（档位 2/5）
func should_lower_wrong_volume() -> bool:
	return value() == VALUE_LOW_WRONG_VOLUME or value() == VALUE_ALL_REDUCED


# 是否不填红（档位 3/5，同时影响错标动画名）
func should_skip_red_fill() -> bool:
	return value() == VALUE_NO_RED_FILL or value() == VALUE_ALL_REDUCED


# 是否降低失败音效（档位 4/5）
func should_lower_fail_volume() -> bool:
	return value() == VALUE_LOW_FAIL_VOLUME or value() == VALUE_ALL_REDUCED
