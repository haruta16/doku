# 过关步数 toast 实验：按步数档位(p5/p10/p20)决定弹不弹；0=对照组（不弹） 1=只弹 p5 档 2=弹到 p10 档 3=弹到 p20 档
extends AbConfigBase
class_name WinToastConfig

# ---- 分组取值（数值即覆盖到的档位号） ----
const VALUE_CONTROL: int = 0 # 对照组，不弹 toast
const VALUE_P5: int = 1 # 只覆盖 p5 档
const VALUE_P10: int = 2 # 覆盖到 p10 档
const VALUE_P20: int = 3 # 覆盖到 p20 档


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "win_toast"
	default_value = VALUE_CONTROL # 默认档：不弹
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否启用（非对照组）
func is_enabled() -> bool:
	return value() != VALUE_CONTROL


# 该步数档位是否在覆盖范围内；tier < 0（未达任何档）一律不弹
func covers_tier(tier: int) -> bool:
	if tier < 0:
		return false
	return value() >= maxi(1, tier)
