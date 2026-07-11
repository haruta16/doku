class_name ProtectScheme
extends RefCounted

const VALUE_NO_PROTECT: String = "no"

const SCHEME_SESSION_GAME_PREFIX: String = "session_game_"
const SCHEME_DAY_GAME_PREFIX: String = "day_game_"
const SCHEME_FIRST_DAY_PREFIX: String = "first_day_"
const SCHEME_DAY_MIN_PREFIX: String = "day_min_"
const SCHEME_SESSION_MIN_PREFIX: String = "session_min_"


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


static func days_since_first_open() -> int:
	var first_ms: int = GameState.get_first_open_time_ms()
	if first_ms <= 0:
		return -1
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var first_local_day: int = int(floor((float(first_ms) / 1000.0 + bias_sec) / 86400.0))
	var today_local_day: int = int(floor((Time.get_unix_time_from_system() + bias_sec) / 86400.0))
	return today_local_day - first_local_day


static func _parse_n(scheme: String, prefix: String) -> int:
	var n_str: String = scheme.substr(prefix.length())
	if not n_str.is_valid_int():
		return -1
	return n_str.to_int()
