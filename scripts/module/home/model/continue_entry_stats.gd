## 续玩入口统计：从残局快照判断有效进度，并计算展示百分比与用时。
extends RefCounted
class_name ContinueEntryStats

const SNAP_KEY_CLOCK_STARTED: String = "continue_clock_started"

const SNAP_KEY_PLAY_SEC: String = "continue_play_sec"

const PERCENT_MAX: float = 99.9

const PERCENT_STEP: float = 0.1

const PLAY_SEC_MAX: int = 3599


## 要求当前关卡、仍有生命且玩家实际操作过，预填猫本身不算续玩进度。
static func has_player_progress(snap: Dictionary, current_level: int) -> bool:
	if snap.is_empty():
		return false
	if int(snap.get("level", 0)) != current_level:
		return false
	if int(snap.get("lives", 0)) <= 0:
		return false
	var prefill_n: int = (snap.get("prefill_positions", []) as Array).size()
	var placed_n: int = (snap.get("placed_cats", []) as Array).size()
	var has_marks: bool = not (snap.get("marks", []) as Array).is_empty()
	var has_errors: bool = not (snap.get("errors", []) as Array).is_empty()
	return placed_n > prefill_n or has_marks or has_errors


static func is_legacy_snapshot(snap: Dictionary) -> bool:
	return not snap.has(SNAP_KEY_CLOCK_STARTED)


## 取放猫比例与已操作格子比例的较大者，显示最多 99.9%，避免未结束却显示完成。
static func progress_percent(snap: Dictionary) -> float:
	var n: int = int(snap.get("size", 0))
	if n <= 0:
		return 0.0
	var placed_n: int = (snap.get("placed_cats", []) as Array).size()
	var marks_n: int = (snap.get("marks", []) as Array).size()
	var errors_n: int = (snap.get("errors", []) as Array).size()
	var cat_ratio: float = float(placed_n) / float(n)
	var cell_ratio: float = float(placed_n + marks_n + errors_n) / float(n * n)
	var progress: float = maxf(cat_ratio, cell_ratio)
	return minf(snappedf(progress * 100.0, PERCENT_STEP), PERCENT_MAX)


static func format_percent(pct: float) -> String:
	return "%.1f%%" % pct


## 把秒数显示为 MM:SS，上限 3599 秒即 59:59。
static func format_play_time(sec: float) -> String:
	var total: int = mini(floori(maxf(sec, 0.0)), PLAY_SEC_MAX)
	return "%02d:%02d" % [total / 60, total % 60]
