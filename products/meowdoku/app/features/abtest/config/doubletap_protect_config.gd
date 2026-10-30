## 实验配置 doubletap_protect：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DoubletapProtectConfig

const VALUE_CONTROL: int = 0
const VALUE_SHORTEN: int = 1
const VALUE_BY_TRUTH: int = 2
const VALUE_BY_CONFLICT: int = 3

const VALUE_WINDOW_300: int = 4
const VALUE_HIGH_FREQ_PROMOTE: int = 5
const VALUE_HIGH_FREQ_AUTOFIX: int = 6
const VALUE_HIGH_FREQ_LOCK: int = 7

const LONG_SEC: float = 0.35
const SHORT_SEC: float = 0.25

const WINDOW_300_SEC_DEFAULT: float = 0.3

const HIGH_FREQ_WINDOW_SEC_DEFAULT: float = 0.65

const HIGH_FREQ_CD_SEC_DEFAULT: float = 0.66

const HIGH_FREQ_LOCK_CD_SEC_DEFAULT: float = 0.25


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "doubletap_protect"
	default_value = VALUE_CONTROL


func window_sec(truth_has_cat: bool, would_conflict: bool) -> float:
	match value():
		VALUE_SHORTEN:
			return SHORT_SEC
		VALUE_BY_TRUTH:
			return LONG_SEC if truth_has_cat else SHORT_SEC
		VALUE_BY_CONFLICT:
			return SHORT_SEC if would_conflict else LONG_SEC
		VALUE_WINDOW_300:
			return window_300_sec()

	return LONG_SEC


func needs_truth() -> bool:
	return value() == VALUE_BY_TRUTH


func needs_conflict() -> bool:
	return value() == VALUE_BY_CONFLICT


func should_promote_tap(truth_has_cat: bool) -> bool:
	return value() == VALUE_HIGH_FREQ_PROMOTE and truth_has_cat and is_high_freq_active()


func is_promote_group() -> bool:
	return value() == VALUE_HIGH_FREQ_PROMOTE


func is_autofix_group() -> bool:
	return value() == VALUE_HIGH_FREQ_AUTOFIX


func should_autofix() -> bool:
	return is_autofix_group() and is_high_freq_active()


static func pick_autofix_target(
	origin: Vector2i, candidates: Array, pixel_dist_sq: Array = []
) -> Vector2i:
	var has_pixel: bool = pixel_dist_sq.size() == candidates.size() and not candidates.is_empty()
	var best: Vector2i = Vector2i(-1, -1)
	var best_dist_sq: int = 2147483647
	var best_pixel_sq: float = INF
	var tie: bool = false
	for i in candidates.size():
		var cell: Vector2i = candidates[i] as Vector2i
		var delta: Vector2i = cell - origin
		var dist_sq: int = delta.x * delta.x + delta.y * delta.y
		var pixel_sq: float = float(pixel_dist_sq[i]) if has_pixel else 0.0
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_pixel_sq = pixel_sq
			best = cell
			tie = false
		elif dist_sq == best_dist_sq:
			if not has_pixel:
				tie = true
			elif pixel_sq < best_pixel_sq:
				best_pixel_sq = pixel_sq
				best = cell
	if tie:
		return Vector2i(-1, -1)
	return best


func should_lock_after_mark_or_error() -> bool:
	return value() == VALUE_HIGH_FREQ_LOCK and is_high_freq_active()


var _last_double_tap_ms: int = -1
var _high_freq_until_ms: int = -1


func _uses_high_freq_state() -> bool:
	var group: int = int(value())
	return (
		group == VALUE_HIGH_FREQ_PROMOTE
		or group == VALUE_HIGH_FREQ_AUTOFIX
		or group == VALUE_HIGH_FREQ_LOCK
	)


func is_high_freq_active() -> bool:
	if not _uses_high_freq_state():
		return false
	return _high_freq_until_ms >= 0 and Time.get_ticks_msec() < _high_freq_until_ms


func notify_double_tap(was_correct: bool) -> void:
	if not _uses_high_freq_state():
		return
	if not was_correct:
		return
	var now_ms: int = Time.get_ticks_msec()
	var until_ms: int = compute_high_freq_until_ms(
		now_ms,
		_last_double_tap_ms,
		int(high_freq_window_sec() * 1000.0),
		int(high_freq_cd_sec() * 1000.0)
	)
	if until_ms >= 0:
		_high_freq_until_ms = until_ms
	_last_double_tap_ms = now_ms


static func compute_high_freq_until_ms(
	now_ms: int, last_double_tap_ms: int, window_ms: int, cd_ms: int
) -> int:
	if last_double_tap_ms < 0:
		return -1
	if (now_ms - last_double_tap_ms) >= window_ms:
		return -1
	return now_ms + cd_ms


func reset_high_freq_state() -> void:
	_last_double_tap_ms = -1
	_high_freq_until_ms = -1


func high_freq_remaining_sec() -> float:
	if not is_high_freq_active():
		return 0.0
	return float(_high_freq_until_ms - Time.get_ticks_msec()) / 1000.0


func window_300_sec() -> float:
	return _dbg_window_300_override if _dbg_window_300_override >= 0.0 else WINDOW_300_SEC_DEFAULT


func high_freq_window_sec() -> float:
	return (
		_dbg_high_freq_window_override
		if _dbg_high_freq_window_override >= 0.0
		else HIGH_FREQ_WINDOW_SEC_DEFAULT
	)


func high_freq_cd_sec() -> float:
	return (
		_dbg_high_freq_cd_override
		if _dbg_high_freq_cd_override >= 0.0
		else HIGH_FREQ_CD_SEC_DEFAULT
	)


func high_freq_lock_cd_sec() -> float:
	return (
		_dbg_high_freq_lock_cd_override
		if _dbg_high_freq_lock_cd_override >= 0.0
		else HIGH_FREQ_LOCK_CD_SEC_DEFAULT
	)


static var _dbg_window_300_override: float = -1.0
static var _dbg_high_freq_window_override: float = -1.0
static var _dbg_high_freq_cd_override: float = -1.0
static var _dbg_high_freq_lock_cd_override: float = -1.0


static func debug_set_window_300_override(sec: float) -> void:
	_dbg_window_300_override = sec


static func debug_window_300_is_overridden() -> bool:
	return _dbg_window_300_override >= 0.0


static func debug_set_high_freq_window_override(sec: float) -> void:
	_dbg_high_freq_window_override = sec


static func debug_high_freq_window_is_overridden() -> bool:
	return _dbg_high_freq_window_override >= 0.0


static func debug_set_high_freq_cd_override(sec: float) -> void:
	_dbg_high_freq_cd_override = sec


static func debug_high_freq_cd_is_overridden() -> bool:
	return _dbg_high_freq_cd_override >= 0.0


static func debug_set_high_freq_lock_cd_override(sec: float) -> void:
	_dbg_high_freq_lock_cd_override = sec


static func debug_high_freq_lock_cd_is_overridden() -> bool:
	return _dbg_high_freq_lock_cd_override >= 0.0
