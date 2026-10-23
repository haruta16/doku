## 实验配置 prop_highlight：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PropHighlightConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组（走原高亮逻辑）
const VALUE_LOCATE_ONCE: int = 1 # 只高亮「定位」道具一次
const VALUE_HINT_ONCE: int = 2 # 只高亮「提示」道具一次
const VALUE_NONE: int = 3 # 不做高亮
const VALUE_CONTROL_REPEATABLE: int = 4 # 对照组逻辑，但允许重复高亮
const VALUE_HINT_10S: int = 5
const VALUE_HINT_FIRST3DAYS: int = 6
const VALUE_RANDOM_ONCE_PER_ROUND: int = 7
const VALUE_DEAD_BOARD: int = 8
const VALUE_OPENING_QUIET: int = 9

const DEAD_BOARD_VISIBLE_WAIT_SEC: float = 5.0

const DEAD_BOARD_HARD_HINT_WAIT_SEC: float = 20.0

const OPENING_QUIET_MEDIAN_FRACTION: float = 0.25


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "prop_highlight"
	default_value = VALUE_RANDOM_ONCE_PER_ROUND


func triggers_on_dead_board() -> bool:
	return value() == VALUE_DEAD_BOARD


func has_opening_quiet_window() -> bool:
	return value() == VALUE_OPENING_QUIET


static func opening_quiet_window_sec(size: int, rank: int) -> float:
	return LevelPassTimeMedian.median_sec(size, rank) * OPENING_QUIET_MEDIAN_FRACTION


static func pick_dead_board_tool(
	candidates: Array[String], stocked: Array[String], ad_unavailable: bool
) -> String:
	if candidates.is_empty():
		return ""
	if stocked.is_empty() and ad_unavailable:
		return ""
	var pool: Array[String] = candidates if stocked.is_empty() else stocked
	return pool[randi() % pool.size()]
