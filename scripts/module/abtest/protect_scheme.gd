# 广告额外保护方案解析器：把 "{session_game_2}" 这类方案串翻译成「是否拦截本次广告」
class_name ProtectScheme
extends RefCounted

# ---- 方案串：<前缀><数字>，如 session_game_2；"no" 表示不保护 ----
const VALUE_NO_PROTECT: String = "no" # 不设保护，直接放行

const SCHEME_SESSION_GAME_PREFIX: String = "session_game_" # 本 session 完局数达 n 局才放行
const SCHEME_DAY_GAME_PREFIX: String = "day_game_" # 今日完局数达 n 局才放行
const SCHEME_FIRST_DAY_PREFIX: String = "first_day_" # 距首次启动满 n-1 天才放行
const SCHEME_DAY_MIN_PREFIX: String = "day_min_" # 今日前台活跃满 n 分钟才放行
const SCHEME_SESSION_MIN_PREFIX: String = "session_min_" # 本 session 前台活跃满 n 分钟才放行


# 按前缀分派到对应判据，返回 {blocked, reason}；无法识别的方案一律放行
static func eval_scheme(scheme: String) -> Dictionary:
	if scheme == VALUE_NO_PROTECT:
		return {"blocked": false, "reason": ""}
	if scheme.begins_with(SCHEME_SESSION_GAME_PREFIX):
		return _eval_count(
			scheme,
			SCHEME_SESSION_GAME_PREFIX,
			GameState.get_session_played_count(),
			"本 session 完局数"
		)
	if scheme.begins_with(SCHEME_DAY_GAME_PREFIX):
		return _eval_count(
			scheme, SCHEME_DAY_GAME_PREFIX, GameState.get_today_played_count(), "今日完局数"
		)
	if scheme.begins_with(SCHEME_FIRST_DAY_PREFIX):
		return _eval_first_day(scheme)
	if scheme.begins_with(SCHEME_DAY_MIN_PREFIX):
		return _eval_minutes(
			scheme, SCHEME_DAY_MIN_PREFIX, SessionManager.get_today_active_sec(), "今日前台活跃"
		)
	if scheme.begins_with(SCHEME_SESSION_MIN_PREFIX):
		return _eval_minutes(
			scheme,
			SCHEME_SESSION_MIN_PREFIX,
			SessionManager.get_session_active_sec(),
			"本 session 前台活跃"
		)

	return {"blocked": false, "reason": ""}


# 完局数门槛：打完 n-1 局之前拦截，即第 n 局起放行
static func _eval_count(
	scheme: String, prefix: String, played_count: int, label: String
) -> Dictionary:
	var n: int = _parse_n(scheme, prefix)
	if n < 0:
		return {"blocked": false, "reason": ""}
	if played_count < (n - 1):
		return {
			"blocked": true, "reason": "%s %d < 门槛 %d(%s)" % [label, played_count, n - 1, scheme]
		}
	return {"blocked": false, "reason": ""}


# 前台活跃时长门槛：不足 n 分钟就拦截
static func _eval_minutes(
	scheme: String, prefix: String, active_sec: int, label: String
) -> Dictionary:
	var n: int = _parse_n(scheme, prefix)
	if n < 0:
		return {"blocked": false, "reason": ""}
	var threshold_sec: int = n * 60
	if active_sec < threshold_sec:
		return {
			"blocked": true,
			"reason": "%s %d 秒 < 门槛 %d 秒(%s)" % [label, active_sec, threshold_sec, scheme]
		}
	return {"blocked": false, "reason": ""}


# 首启天数门槛：距首次启动不足 n-1 天就拦截；取不到首启时间则放行
static func _eval_first_day(scheme: String) -> Dictionary:
	var n: int = _parse_n(scheme, SCHEME_FIRST_DAY_PREFIX)
	if n < 0:
		return {"blocked": false, "reason": ""}
	var days_since: int = days_since_first_open()
	if days_since < 0:
		return {"blocked": false, "reason": ""}
	if days_since < (n - 1):
		return {"blocked": true, "reason": "距首启 %d 天 < 门槛 %d 天(%s)" % [days_since, n - 1, scheme]}
	return {"blocked": false, "reason": ""}


# 距首次启动的自然天数（按本地时区整除到「天」）；拿不到首启时间返回 -1
static func days_since_first_open() -> int:
	var first_ms: int = GameState.get_first_open_time_ms()
	if first_ms <= 0:
		return -1
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var first_local_day: int = int(floor((float(first_ms) / 1000.0 + bias_sec) / 86400.0))
	var today_local_day: int = int(floor((Time.get_unix_time_from_system() + bias_sec) / 86400.0))
	return today_local_day - first_local_day


# 取出前缀后的整数；不是合法数字返回 -1，调用方据此放行
static func _parse_n(scheme: String, prefix: String) -> int:
	var n_str: String = scheme.substr(prefix.length())
	if not n_str.is_valid_int():
		return -1
	return n_str.to_int()
