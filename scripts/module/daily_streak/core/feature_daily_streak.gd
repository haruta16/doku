extends Node

const SAVE_PATH := "user://streak.cfg"
const CYCLE_LENGTH: int = 7

signal streak_updated(data: StreakData)
signal checkin_completed(result: Dictionary)
signal reward_claimed(reward: Dictionary)

var _data: StreakData = StreakData.new()

var _pending_show_uid: int = -1

var _pending_switch_eligible: bool = false

var _last_seen_jdn: int = 0


func _ready() -> void:
	_load_data()

	_pending_switch_eligible = _data.pending_switch_page > 0
	_check_continuity()
	GameState.all_data_reset.connect(reset)

	_last_seen_jdn = _today_jdn()
	var watch := Timer.new()
	watch.wait_time = 1.0
	watch.one_shot = false
	watch.autostart = true
	watch.timeout.connect(_on_day_watch_tick)
	add_child(watch)


func _on_day_watch_tick() -> void:
	var today_jdn: int = _today_jdn()
	if today_jdn == _last_seen_jdn:
		return
	_last_seen_jdn = today_jdn
	_check_continuity()
	streak_updated.emit(_data)


func get_ab_group() -> int:
	return ABTestManager.daily_streak.value()


func is_enabled() -> bool:
	return ABTestManager.daily_streak.is_enabled()


func has_reward() -> bool:
	return ABTestManager.daily_streak.has_reward()


func should_skip_lit() -> bool:
	return ABTestManager.daily_streak.is_skip_lit()


func is_unlocked() -> bool:
	if not is_enabled():
		return false
	return GameState.is_tutorial_done()


func notify_group_dyed() -> void:
	var cur: int = get_ab_group()
	print(
		(
			"[StreakSwitch] notify_group_dyed: cur=%d last_group=%d pending=%d"
			% [cur, _data.last_group, _data.pending_switch_page]
		)
	)
	if _data.last_group == -1:
		if cur != 0:
			_data.last_group = cur
			_save_data()
		print("[StreakSwitch] notify: 首次记录 last_group=%d (cur=%d),不弹" % [_data.last_group, cur])
		return
	if cur == _data.last_group:
		print("[StreakSwitch] notify: cur==last_group(%d),无切组" % cur)
		return

	var page: int = _map_switch_page(_data.last_group, cur)
	if page > 0:
		_data.pending_switch_page = page

		_pending_switch_eligible = true
	print(
		(
			"[StreakSwitch] notify: 切组 %d->%d 映射 page=%d pending=%d eligible=%s"
			% [
				_data.last_group,
				cur,
				page,
				_data.pending_switch_page,
				str(_pending_switch_eligible)
			]
		)
	)

	_data.last_group = cur if cur != 0 else -1
	_save_data()


func _map_switch_page(old_group: int, new_group: int) -> int:
	if (old_group == 1 or old_group == 2 or old_group == 4) and (new_group == 0 or new_group == 3):
		return 1
	if old_group == 3 and new_group == 0:
		return 2
	if old_group == 3 and (new_group == 1 or new_group == 2 or new_group == 4):
		return 3
	return 0


func get_pending_switch_page() -> int:
	return _data.pending_switch_page if _pending_switch_eligible else 0


func consume_pending_switch() -> void:
	_data.pending_switch_page = 0
	_pending_switch_eligible = false
	_save_data()


func grant_switch_gift() -> void:
	var items: Array = _build_reward_items()
	if items.is_empty():
		return
	AwardManager.dispatch(items, AwardManager.DisplayType.DIRECT, Tracker.PropSource.SWITCH_GROUP)


func can_checkin_today() -> bool:
	return _data.last_checkin_date != _today_str()


func is_win_qualifies(source: StringName) -> bool:
	if not is_enabled():
		return false
	if ABTestManager.daily_streak.is_challenge_only():
		return source == &"challenge"
	return source == &"main" or source == &"challenge"


func notify_win(source: StringName) -> void:
	if not is_unlocked():
		return
	if not can_checkin_today():
		return
	if not is_win_qualifies(source):
		return
	do_checkin()


func do_checkin() -> Dictionary:
	var today := _today_str()
	_data.last_checkin_date = today

	_data.current_streak += 1
	_data.reward_cycle_day += 1

	if _data.current_streak > _data.best_streak:
		_data.best_streak = _data.current_streak

	if _data.streak_start_weekday < 0:
		_data.streak_start_weekday = _today_weekday()

	_pending_show_uid = 0

	var has_reward := false
	if _data.reward_cycle_day > 0 and _data.reward_cycle_day % CYCLE_LENGTH == 0:
		if ABTestManager.daily_streak.has_reward():
			has_reward = true

			var items: Array = _build_reward_items()
			var uid: int = (
				AwardManager
				. dispatch(
					items,
					AwardManager.DisplayType.STREAK_GIFT,
					Tracker.PropSource.STREAK_CHEST,
					Tracker.PropSource.STREAK_REWARD_AD,
				)
			)
			_pending_show_uid = uid

	_save_data()

	Tracker.track_spark_streak(_data.current_streak, _data.best_streak)

	var result := {
		"streak": _data.current_streak,
		"best_streak": _data.best_streak,
		"has_reward": has_reward,
		"is_new_streak": _data.current_streak == 1,
	}
	checkin_completed.emit(result)
	streak_updated.emit(_data)
	return result


func get_data() -> StreakData:
	return _data


func get_week_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var start_wd: int = (
		_data.streak_start_weekday if _data.streak_start_weekday >= 0 else _today_weekday()
	)
	var filled: int = 0
	if _data.reward_cycle_day > 0:
		var mod: int = _data.reward_cycle_day % CYCLE_LENGTH
		if mod == 0:
			if _data.last_checkin_date == _today_str():
				filled = CYCLE_LENGTH
		else:
			filled = mod
	for i: int in range(CYCLE_LENGTH):
		var wd: int = (start_wd + i) % 7
		var checked: bool = i < filled
		slots.append({"weekday": wd, "checked": checked})
	return slots


func has_pending_show() -> bool:
	return _pending_show_uid >= 0


func get_pending_show_uid() -> int:
	return _pending_show_uid


func claim_reward(_double: bool = false) -> Dictionary:
	if _pending_show_uid < 0:
		return {}
	if _pending_show_uid > 0:
		AwardManager.show_award(_pending_show_uid)
	streak_updated.emit(_data)
	return {}


func consume_pending_show() -> void:
	_pending_show_uid = -1


func reset() -> void:
	_data = StreakData.new()
	_pending_show_uid = -1
	_pending_switch_eligible = false
	_save_data()
	streak_updated.emit(_data)


func _check_continuity() -> void:
	if _data.last_checkin_date.is_empty():
		return
	var last_jdn: int = _date_str_to_jdn(_data.last_checkin_date)
	var today_jdn: int = _today_jdn()
	var diff: int = today_jdn - last_jdn
	if diff > 1:
		_data.current_streak = 0
		_data.reward_cycle_day = 0
		_data.streak_start_weekday = -1

		_pending_show_uid = -1
		_save_data()


func _build_reward() -> Dictionary:
	return StreakData.REWARD_BASE.duplicate()


func _build_reward_items() -> Array:
	var items: Array = []
	for kind: String in StreakData.REWARD_BASE:
		var count: int = int(StreakData.REWARD_BASE[kind])
		if count > 0:
			items.append(AwardItem.make(kind, count))
	return items


func _save_data() -> void:
	var cfg := ConfigFile.new()
	var d: Dictionary = _data.to_dict()
	for k: String in d:
		cfg.set_value("streak", k, d[k])
	cfg.save(SAVE_PATH)


func _load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var d: Dictionary = {}
	for k: String in cfg.get_section_keys("streak"):
		d[k] = cfg.get_value("streak", k)
	_data = StreakData.from_dict(d)


func cheat_setup_six_days() -> void:
	_data.current_streak = 6
	_data.reward_cycle_day = 6
	_data.best_streak = max(_data.best_streak, 6)
	_data.last_checkin_date = _date_offset_str(-1)
	_data.streak_start_weekday = (_today_weekday() - 6 + 7) % 7
	_pending_show_uid = -1
	_save_data()
	streak_updated.emit(_data)


func cheat_clear_today() -> void:
	if _data.last_checkin_date != _today_str():
		push_warning("[StreakCheat] 今天本来就没打卡,clear no-op")
		return
	_data.last_checkin_date = _date_offset_str(-1)
	_data.current_streak = max(0, _data.current_streak - 1)
	_data.reward_cycle_day = max(0, _data.reward_cycle_day - 1)
	if _data.current_streak == 0:
		_data.streak_start_weekday = -1
	_pending_show_uid = -1
	_save_data()
	streak_updated.emit(_data)


func cheat_skip_day() -> void:
	if _data.last_checkin_date.is_empty():
		push_warning("[StreakCheat] last_checkin_date 空,跳过 skip")
		return
	_data.last_checkin_date = _date_offset_str_from(_data.last_checkin_date, -1)
	_check_continuity()
	streak_updated.emit(_data)


static func _date_offset_str(days: int) -> String:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return _date_offset_str_from("%d-%02d-%02d" % [dt.year, dt.month, dt.day], days)


static func _date_offset_str_from(base_date_str: String, days: int) -> String:
	var parts: PackedStringArray = base_date_str.split("-")
	if parts.size() < 3:
		return base_date_str
	var unix: int = (
		Time
		. get_unix_time_from_datetime_dict(
			{
				"year": parts[0].to_int(),
				"month": parts[1].to_int(),
				"day": parts[2].to_int(),
				"hour": 0,
				"minute": 0,
				"second": 0,
			}
		)
	)
	var off: Dictionary = Time.get_datetime_dict_from_unix_time(unix + days * 86400)
	return "%d-%02d-%02d" % [off.year, off.month, off.day]


static func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


static func _today_weekday() -> int:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return dt.weekday as int


static func _today_jdn() -> int:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return _local_date_to_jdn(dt.year, dt.month, dt.day)


static func _date_str_to_jdn(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return 0
	return _local_date_to_jdn(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())


static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
