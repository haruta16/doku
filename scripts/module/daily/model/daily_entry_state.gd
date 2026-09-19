# 每日挑战入口的纯逻辑：三态判定（未解锁 / 可玩 / 今日已完成）+ 日期、倒计时、成绩文案
# 全部是 static，不碰节点；主页入口格 daily_challenge_entry_cell 直接调这里
class_name DailyEntryState
extends RefCounted

enum State { LOCKED, NORMAL, DONE } # 入口三态：LOCKED 未解锁 / NORMAL 今天可玩 / DONE 今天已完成

const UNLOCK_LEVEL: int = 21 # 解锁门槛：主线打到第 21 关才开放每日挑战

# 月份缩写翻译 key，下标 1~12 对应一月~十二月，第 0 项是占位空串
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


# 算出口三态：先看等级够不够，再看今天是不是已经翻篇
static func compute_state() -> int:
	if GameState.get_current_level() < UNLOCK_LEVEL:
		return State.LOCKED
	var today: String = _today_str()
	# 已完成 = 今天通关过，或者今天已经落后于 max_daily_date（这一天已被翻过去）
	if GameState.get_daily_completed_date() == today or today < GameState.get_max_daily_date():
		return State.DONE
	return State.NORMAL


# 今天的日期文案（如 "Jun 3"），月份走翻译表
static func today_date_text() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%s %d" % [TranslationServer.translate(_MONTH_ABBR[int(dt.month)]), int(dt.day)]


# 距次日 0 点还剩多久，返回 HH:MM:SS（按本地系统时间算）
static func countdown_text() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var remaining: int = 86400 - int(dt.hour) * 3600 - int(dt.minute) * 60 - int(dt.second) # 86400 减去已过秒数 = 距次日 0 点的剩余秒数
	@warning_ignore("integer_division")
	return "%02d:%02d:%02d" % [remaining / 3600, (remaining % 3600) / 60, remaining % 60]


# 今日通关耗时的 MM:SS 文案，数据来自存档里的 daily_elapsed_sec
static func done_time_text() -> String:
	var sec: int = GameState.get_daily_elapsed_sec() # 秒数来自存档，不是实时计时
	@warning_ignore("integer_division")
	return "%02d:%02d" % [sec / 60, sec % 60]


# 今日成绩排名的 TOP x% 文案；beat_percent 是「打赢了百分之多少的人」，所以取 100 减
static func done_rank_text() -> String:
	# 结果刚好是整数时不显示小数位
	var top: float = snappedf(100.0 - GameState.get_daily_beat_percent(), 0.1)
	var decimals: int = 0 if is_equal_approx(top, roundf(top)) else 1
	return TranslationServer.translate("HOME_DAILY_TOP_PERCENT") % I18nFormat.percent(top, decimals)


# 入口点击的统一处理：未解锁/已完成各弹一条 Toast，可玩时走回调或直接打开每日页
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


# 把存档里的 max_daily_date 推进到今天（主页每次显示时调用，只增不减）
static func ensure_max_daily_advanced() -> void:
	GameState.advance_max_daily_date(_today_str())


# 今天的日期字符串 yyyy-mm-dd，存档比较都用它
static func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]
