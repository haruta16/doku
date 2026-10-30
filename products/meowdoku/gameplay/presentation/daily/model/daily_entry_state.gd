## 每日挑战入口状态：结合解锁进度、日期与重玩实验决定按钮行为和显示文案。
class_name DailyEntryState
extends RefCounted

enum State { LOCKED, NORMAL, DONE, REPLAY }

const UNLOCK_LEVEL: int = 21 # 解锁门槛：主线打到第 21 关才开放每日挑战

## 月份缩写翻译 key，下标 1~12 对应一月~十二月，第 0 项是占位空串
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


## 先检查主线解锁门槛，再比较本地日期和历史最大日期，区分正常、完成与今日重玩。
static func compute_state() -> int:
	if GameState.get_current_level() < UNLOCK_LEVEL:
		return State.LOCKED
	var today: String = _today_str()
	if today < GameState.get_max_daily_date():
		return State.DONE
	if GameState.get_daily_completed_date() == today:
		return State.REPLAY
	return State.NORMAL


## 今日完成状态还需通过装扮实验的重玩开关，不能只看日期。
static func can_replay_today() -> bool:
	return compute_state() == State.REPLAY and ABTestManager.dc_costume.can_replay()


static func is_done_like(state: int) -> bool:
	return state == State.DONE or state == State.REPLAY


## 今天的日期文案（如 "Jun 3"），月份走翻译表
static func today_date_text() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%s %d" % [TranslationServer.translate(_MONTH_ABBR[int(dt.month)]), int(dt.day)]


## 距次日 0 点还剩多久，返回 HH:MM:SS（按本地系统时间算）
static func countdown_text() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var remaining: int = 86400 - int(dt.hour) * 3600 - int(dt.minute) * 60 - int(dt.second) # 86400 减去已过秒数 = 距次日 0 点的剩余秒数
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [remaining / 3600, (remaining % 3600) / 60, remaining % 60]


## 今日通关耗时的 MM:SS 文案，数据来自存档里的 daily_elapsed_sec
static func done_time_text() -> String:
	var sec: int = GameState.get_daily_elapsed_sec() # 秒数来自存档，不是实时计时
	@warning_ignore("integer_division")
	return "%02d:%02d" % [sec / 60, sec % 60]


## 今日成绩排名的 TOP x% 文案；beat_percent 是「打赢了百分之多少的人」，所以取 100 减
static func done_rank_text() -> String:
	# 结果刚好是整数时不显示小数位
	var top: float = snappedf(100.0 - GameState.get_daily_beat_percent(), 0.1)
	var decimals: int = 0 if is_equal_approx(top, roundf(top)) else 1
	return TranslationServer.translate("HOME_DAILY_TOP_PERCENT") % I18nFormat.percent(top, decimals)


## 按统一入口状态显示提示或调用正常、重玩回调，默认正常入口打开每日挑战。
static func handle_click(
	host: Node, on_normal: Callable = Callable(), on_replay: Callable = Callable()
) -> void:
	match compute_state():
		State.LOCKED:
			Toast.popup("HOME_TOAST_DAILY_LOCKED", host)
		State.DONE:
			Toast.popup("HOME_TOAST_DAILY_DONE", host)
		State.REPLAY:
			if ABTestManager.dc_costume.can_replay() and on_replay.is_valid():
				on_replay.call()
			else:
				Toast.popup("HOME_TOAST_DAILY_DONE", host)
		State.NORMAL:
			if on_normal.is_valid():
				on_normal.call()
			else:
				UIManager.show_ui(UiName.DAILY_GAME, {})


## 把存档里的 max_daily_date 推进到今天（主页每次显示时调用，只增不减）
static func ensure_max_daily_advanced() -> void:
	GameState.advance_max_daily_date(_today_str())


## 今天的日期字符串 yyyy-mm-dd，存档比较都用它
static func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]
