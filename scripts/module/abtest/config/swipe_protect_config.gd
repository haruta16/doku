## 实验配置 swipe_protect：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name SwipeProtectConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不用防误触判定器
const VALUE_HOTZONE_40: int = 1 # 吸附容差 40% 格宽
const VALUE_HOTZONE_10: int = 2 # 吸附容差 10% 格宽
const VALUE_HOTZONE_RAISED: int = 3 # 容差 40%，但限 7 格以上棋盘且滑动门槛抬高
const VALUE_HOTZONE_30: int = 4
const VALUE_HOTZONE_20: int = 5
const VALUE_HOTZONE_50: int = 6
const VALUE_DYNAMIC_INTENT: int = 7
const VALUE_NEXT_CELL: int = 8
const VALUE_CELL_NEIGHBOR: int = 9
const VALUE_TARGET_COLOR_20: int = 10
const VALUE_TARGET_COLOR_0: int = 11

const HOTZONE_TOL_PCT: float = 0.4

const TARGET_COLOR_TOL_PCT_20: float = 0.2
const TARGET_COLOR_TOL_PCT_0: float = 0.0

static var _dbg_tc_tol_pct_override: float = -1.0


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "swipe_protect"
	default_value = VALUE_HOTZONE_40


func has_target_color_protection() -> bool:
	return has_target_color_protection_for(int(value()))


func target_color_tol_pct() -> float:
	return target_color_tol_pct_for(int(value()))


static func debug_set_tc_tol_pct_override(pct: float) -> void:
	_dbg_tc_tol_pct_override = pct


static func debug_tc_tol_pct_is_overridden() -> bool:
	return _dbg_tc_tol_pct_override >= 0.0


static func debug_tc_tol_pct_override_value() -> float:
	return _dbg_tc_tol_pct_override


static func has_target_color_protection_for(v: int) -> bool:
	return v == VALUE_TARGET_COLOR_20 or v == VALUE_TARGET_COLOR_0


static func target_color_tol_pct_for(v: int) -> float:
	if _dbg_tc_tol_pct_override >= 0.0:
		return _dbg_tc_tol_pct_override
	match v:
		VALUE_TARGET_COLOR_0:
			return TARGET_COLOR_TOL_PCT_0
		_:
			return TARGET_COLOR_TOL_PCT_20
