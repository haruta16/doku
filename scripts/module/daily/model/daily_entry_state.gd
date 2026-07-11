class_name DailyEntryState
extends RefCounted

enum State { LOCKED, NORMAL, DONE }

const UNLOCK_LEVEL: int = 21

const _MONTH_ABBR: Array[String] = [
	"",
	"MONTH_ABBR_1",
	"MONTH_ABBR_2",
	"MONTH_ABBR_3",
	"MONTH_ABBR_4",
	"MONTH_ABBR_5",
	"MONTH_ABBR_6",
	"MONTH_ABBR_7",
	"MONTH_ABBR_8",
	"MONTH_ABBR_9",
	"MONTH_ABBR_10",
	"MONTH_ABBR_11",
	"MONTH_ABBR_12"
]


static func compute_state() -> int:
	if GameState.get_current_level() < UNLOCK_LEVEL:
		return State.LOCKED
	var today: String = _today_str()
	if GameState.get_daily_completed_date() == today or today < GameState.get_max_daily_date():
		return State.DONE
	return State.NORMAL


static func today_date_text() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%s %d" % [TranslationServer.translate(_MONTH_ABBR[int(dt.month)]), int(dt.day)]


static func countdown_text() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var remaining: int = 86400 - int(dt.hour) * 3600 - int(dt.minute) * 60 - int(dt.second)
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [remaining / 3600, (remaining % 3600) / 60, remaining % 60]


static func done_time_text() -> String:
	var sec: int = GameState.get_daily_elapsed_sec()
	@warning_ignore("integer_division")
	return "%02d:%02d" % [sec / 60, sec % 60]


static func done_rank_text() -> String:
	var top: float = snappedf(100.0 - GameState.get_daily_beat_percent(), 0.1)
	var decimals: int = 0 if is_equal_approx(top, roundf(top)) else 1
	return TranslationServer.translate("HOME_DAILY_TOP_PERCENT") % I18nFormat.percent(top, decimals)


static func handle_click(host: Node, on_normal: Callable = Callable()) -> void:
	match compute_state():
		State.LOCKED:
			Toast.popup("HOME_TOAST_DAILY_LOCKED", host)
		State.DONE:
			Toast.popup("HOME_TOAST_DAILY_DONE", host)
		State.NORMAL:
			if on_normal.is_valid():
				on_normal.call()
			else:
				UIManager.show_ui(UiName.DAILY_GAME, {})


static func ensure_max_daily_advanced() -> void:
	GameState.advance_max_daily_date(_today_str())


static func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]
