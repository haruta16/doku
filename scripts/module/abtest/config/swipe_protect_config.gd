# 滑动防误触实验：把滑动坐标吸附到行列上；0=对照组（原手势识别） 1=容差 40% 格宽 2=容差 10% 格宽 3=只在 7 格以上生效且要求滑够 60% 长度
extends AbConfigBase
class_name SwipeProtectConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不用防误触判定器
const VALUE_HOTZONE_40: int = 1 # 吸附容差 40% 格宽
const VALUE_HOTZONE_10: int = 2 # 吸附容差 10% 格宽
const VALUE_HOTZONE_RAISED: int = 3 # 容差 40%，但限 7 格以上棋盘且滑动门槛抬高


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "swipe_protect"
	default_value = VALUE_CONTROL # 默认档：不做防误触
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否启用滑动保护（档位 1/2/3）
func is_enabled() -> bool:
	return value() in [VALUE_HOTZONE_40, VALUE_HOTZONE_10, VALUE_HOTZONE_RAISED]


# 启用保护的最小棋盘尺寸：档位 3 要求 >= 7 格，其余 0（不限）
func min_size() -> int:
	return 7 if value() == VALUE_HOTZONE_RAISED else 0


# 吸附容差占格宽的比例：档位 2 为 0.1，其余 0.4
func tolerance_pct() -> float:
	return 0.1 if value() == VALUE_HOTZONE_10 else 0.4


# 有效滑动需要跨过的格数：档位 3 取 60% 棋盘尺寸向上取整，其余固定 4
func threshold_for(n: int) -> int:
	if value() == VALUE_HOTZONE_RAISED:
		return ceili(n * 0.6)
	return 4
