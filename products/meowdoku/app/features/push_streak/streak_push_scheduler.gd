## 断签提醒调度器：依据最近打卡日期与实验条件，注册或撤销后续每日通知。
extends RefCounted
class_name StreakPushScheduler

const PUSH_ID: String = "streak_broken"

const TRIGGER_HOUR: float = 19.0

const SOUND_NAME: String = "push_sound_g2_eve.wav"

const POOL_SIZE: int = 5

const POOL_TOTAL: int = 100


## 实验或解锁条件不符时撤销通知；否则按最近签到日期重新注册后续每天 19 点提醒。
static func reevaluate(reason: String) -> void:
	if not ABTestManager.push_style.is_normal_push():
		_remove_push("对照组/未知组(style=%d) reason=%s" % [ABTestManager.push_style.value(), reason])
		return
	if not StreakManager.is_unlocked():
		_remove_push("streak未解锁(教程未完成) reason=%s" % reason)
		return

	var last_checkin: String = StreakManager.get_data().last_checkin_date
	var offset: int = baseline_day_offset(last_checkin, _today_str())
	var contents: Array[Dictionary] = _pick_random_contents()
	print(
		(
			"[StreakPush] register reason=%s last_checkin=%s offset=%d(首触发=%s 19:00) contents=%d"
			% [reason, last_checkin, offset, _offset_date_str(offset), contents.size()]
		)
	)

	print(
		(
			"[StreakPush] contents detail: locale=%s now=%s"
			% [TranslationServer.get_locale(), Time.get_datetime_string_from_system()]
		)
	)
	for i: int in contents.size():
		var item: Dictionary = contents[i]
		print(
			(
				"[StreakPush]   c%d title=[%s] content=[%s]"
				% [i, item.get("title", ""), item.get("content", "")]
			)
		)
	UniKitManager.add_daily_push_from_offset(PUSH_ID, offset, TRIGGER_HOUR, contents, 1)


## 今天或未来日期已签到时从两天后开始，其余情况从明天开始。
static func baseline_day_offset(last_checkin_date: String, today_date: String) -> int:
	if last_checkin_date == today_date:
		return 2
	if not last_checkin_date.is_empty() and _date_diff_days(last_checkin_date, today_date) < 0:
		return 2
	return 1


## 翻译 100 组候选并打乱，选出 5 组交给原生通知轮换。
static func _pick_random_contents() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for i: int in range(1, POOL_TOTAL + 1):
		(
			pool
			. append(
				{
					"title": str(TranslationServer.translate("PUSH3_NOCHK_TITLE_%d" % i)),
					"content": str(TranslationServer.translate("PUSH3_NOCHK_BODY_%d" % i)),
					"sound": SOUND_NAME,
				}
			)
		)
	pool.shuffle()
	var picked: Array[Dictionary] = []
	for i: int in mini(POOL_SIZE, pool.size()):
		picked.append(pool[i])
	return picked


static func _remove_push(reason: String) -> void:
	print("[StreakPush] remove reason=%s" % reason)
	UniKitManager.remove_push(PUSH_ID)


static func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


static func _date_diff_days(from_date: String, to_date: String) -> int:
	return _str_to_jdn(to_date) - _str_to_jdn(from_date)


static func _offset_date_str(offset: int) -> String:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	var jdn: int = _date_to_jdn(int(dt.year), int(dt.month), int(dt.day)) + offset
	var date: Dictionary = _jdn_to_date(jdn)
	return "%d-%02d-%02d" % [date.year, date.month, date.day]


static func _str_to_jdn(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() != 3:
		return 0
	return _date_to_jdn(int(parts[0]), int(parts[1]), int(parts[2]))


static func _date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


static func _jdn_to_date(jdn: int) -> Dictionary:
	var a: int = jdn + 32044
	var b: int = (4 * a + 3) / 146097
	var c: int = a - (146097 * b) / 4
	var d: int = (4 * c + 3) / 1461
	var e: int = c - (1461 * d) / 4
	var m: int = (5 * e + 2) / 153
	return {
		"year": 100 * b + d - 4800 + m / 10,
		"month": m + 3 - 12 * (m / 10),
		"day": e - (153 * m + 2) / 5 + 1,
	}
