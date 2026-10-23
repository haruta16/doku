## 连续打卡管理器：维护日期历史、断签补签、周期奖励及存档同步，并通知界面刷新。
extends Node

const SAVE_PATH := "user://streak.cfg" # 存档路径（ConfigFile 格式，只有 [streak] 一段）
const CYCLE_LENGTH: int = 7 # 奖励周期长度：每满 7 天发一次宝箱
const StreakHistory: GDScript = preload("res://scripts/module/daily_streak/core/streak_history.gd")

# ---- 信号 ----
signal streak_updated(data: StreakData) # 打卡数据有变化（打卡 / 断签 / 重置 / 领奖），UI 据此重刷
signal checkin_completed(result: Dictionary) # 本次打卡完成，result 见 do_checkin 的返回值
signal reward_claimed(reward: Dictionary) # 领奖信号（目前没有地方 emit，预留给 UI）

# ---- 运行时状态（_data 会被整份写进存档） ----
var _data: StreakData = StreakData.new() # 内存里的打卡数据，读写存档都以它为准
var _store: SaveStore = SaveStore.plain_file(SAVE_PATH)

var _pending_show_uid: int = -1 # 待展示奖励 uid：-1 无 / 0 只打了卡没奖励 / >0 有奖励待展示

var _revive_anim: Dictionary = {}

var _pending_switch_eligible: bool = false # 本次启动是否允许弹切组说明页；消费后置 false

var _last_seen_jdn: int = 0 # 上次看到的「今天」的儒略日序号，用于跨天检测


## 恢复并修正打卡历史，结清上次未决胜利，再注册云同步和每秒跨日检查。
func _ready() -> void:
	var history_changed: bool = _load_data()
	var had_pending_win: bool = has_pending_revive_decision()

	_resolve_pending_win_checkin()
	if history_changed and not had_pending_win:
		_save_data()

	_pending_switch_eligible = _data.pending_switch_page > 0

	GameState.all_data_reset.connect(reset)

	DataSyncRegistry.register(self)

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
	streak_updated.emit(_data)


# ================= AB 实验开关 =================
## 当前分组编号：0 控制 / 1 基础 / 2 仅挑战 / 3 无奖励 / 4 不点亮
func get_ab_group() -> int:
	return ABTestManager.daily_streak.value()


func is_unlocked() -> bool:
	return GameState.is_tutorial_done()


# ================= 分组切换说明页 =================
## 启动染色后由主页调用：比对存档里的旧分组与当前分组，映射出要弹的说明页
func notify_group_dyed() -> void:
	var cur: int = get_ab_group()
	# 每次判定都打日志，方便排查为什么弹 / 不弹
	print(
		(
			"[StreakSwitch] notify_group_dyed: cur=%d last_group=%d pending=%d"
			% [cur, _data.last_group, _data.pending_switch_page]
		)
	)
	# 第一次运行：只记录当前分组，不弹说明页
	if _data.last_group == -1:
		if cur != 0:
			_data.last_group = cur
			_save_data()
		print("[StreakSwitch] notify: 首次记录 last_group=%d (cur=%d),不弹" % [_data.last_group, cur])
		return
	# 分组没变，不用弹
	if cur == _data.last_group:
		print("[StreakSwitch] notify: cur==last_group(%d),无切组" % cur)
		return

	# 分组变了：映射出说明页编号（0 = 不用弹）并置好待弹标记
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

	# 记录本次分组；控制组记成 -1，下次启动才不会误判成切组
	_data.last_group = cur if cur != 0 else -1
	_save_data()


## 把图标实验组按日期锁入本地存档，避免同一天内远端实验刷新使入口造型跳变。
func get_effective_icon_group() -> int:
	var today: String = _today_str()
	if _data.icon_group < 0 or _data.icon_group_date != today:
		if not ABTestManager.is_app_start_dyed():
			return int(ABTestManager.dailystreak_icon.value())
		_data.icon_group = int(ABTestManager.dailystreak_icon.value())
		_data.icon_group_date = today
		_save_data()
	return _data.icon_group


func cheat_reset_icon_group() -> void:
	_data.icon_group = -1
	_data.icon_group_date = ""
	_save_data()
	streak_updated.emit(_data)


func _map_switch_page(old_group: int, new_group: int) -> int:
	old_group = 1 if old_group in [1, 6, 7] else old_group
	new_group = 1 if new_group in [1, 6, 7] else new_group
	if (old_group == 1 or old_group == 2 or old_group == 4) and (new_group == 0 or new_group == 3):
		return 1
	if old_group == 3 and new_group == 0:
		return 2
	if old_group == 3 and (new_group == 1 or new_group == 2 or new_group == 4):
		return 3
	return 0


## 待弹的说明页编号（0 = 不弹），只有本次启动有资格时才返回
func get_pending_switch_page() -> int:
	return _data.pending_switch_page if _pending_switch_eligible else 0


## 消费掉待弹说明页并写存档（主页弹完就调）
func consume_pending_switch() -> void:
	_data.pending_switch_page = 0
	_pending_switch_eligible = false
	_save_data()


## 补发切组礼包：直接进背包（DIRECT 展示），不走宝箱动画
func grant_switch_gift() -> void:
	var items: Array = _build_reward_items()
	if items.is_empty():
		return
	AwardManager.dispatch(items, AwardManager.DisplayType.DIRECT, Tracker.PropSource.SWITCH_GROUP)


func can_checkin_today() -> bool:
	if _data.last_checkin_date.is_empty():
		return true

	return _today_jdn() > _date_str_to_jdn(_data.last_checkin_date)


func is_win_qualifies(source: StringName) -> bool:
	return source == &"main" or source == &"challenge"


## 游戏胜利时的入口：未解锁 / 今天已打卡 / 胜利类型不符都直接返回，否则打卡
func notify_win(source: StringName) -> void:
	if not is_unlocked():
		return
	if not can_checkin_today():
		return
	if not is_win_qualifies(source):
		return
	do_checkin()


## 记录今日历史，推进或重置连签与奖励周期，写盘后发出完成和刷新信号。
func do_checkin() -> Dictionary:
	var was_broken: bool = is_broken()

	_revive_anim = {}
	_data.pending_win_checkin_date = ""
	var today: String = _today_str()
	_data.last_checkin_date = today
	var today_jdn: int = StreakData.history_date_to_jdn(today)
	_record_history_range(today_jdn, today_jdn)

	_data.last_checkin_minute = _now_minute_of_day()

	if was_broken:
		_data.current_streak = 1
		_data.reward_cycle_day = 1
		_data.streak_start_weekday = _today_weekday()
	else:
		_data.current_streak += 1
		_data.reward_cycle_day += 1
		if _data.streak_start_weekday < 0:
			_data.streak_start_weekday = _today_weekday()

	if _data.current_streak > _data.best_streak:
		_data.best_streak = _data.current_streak

	_pending_show_uid = 0

	var has_reward := false
	if _data.reward_cycle_day > 0 and _data.reward_cycle_day % CYCLE_LENGTH == 0:
		has_reward = true
		_pending_show_uid = _dispatch_streak_chest()

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


func should_offer_revive(source: StringName) -> bool:
	if not is_unlocked():
		return false
	if not can_checkin_today():
		return false
	if not is_win_qualifies(source):
		return false
	if not is_broken():
		return false
	if _data.current_streak < 2:
		return false
	return missed_days() <= StreakProtectConfig.REVIVE_MAX_DAYS_BASELINE


## 胜利满足补签条件时先保存待决日期，否则直接按普通打卡结算。
func settle_win(source: StringName) -> void:
	if should_offer_revive(source):
		mark_pending_win_checkin()
	else:
		notify_win(source)


func has_pending_revive_decision() -> bool:
	return _data.pending_win_checkin_date != ""


func mark_pending_win_checkin() -> void:
	_data.pending_win_checkin_date = _today_str()
	_save_data()


func get_revive_info() -> Dictionary:
	return {
		"broken_streak": _data.current_streak,
		"missed_days": missed_days(),
	}


## 补齐漏签天数和今天，跨奖励周期时派发宝箱，保存后请求同步并通知界面。
func revive_streak() -> Dictionary:
	var missed: int = missed_days()
	var previous_jdn: int = StreakData.history_date_to_jdn(_data.last_checkin_date)
	var today: String = _today_str()
	var today_jdn: int = StreakData.history_date_to_jdn(today)
	var has_reward: bool = false
	_pending_show_uid = 0

	var add: int = missed + 1
	var before_cycle: int = _data.reward_cycle_day
	_data.current_streak += add
	_data.reward_cycle_day += add
	if _data.streak_start_weekday < 0:
		_data.streak_start_weekday = _today_weekday()

	if (_data.reward_cycle_day / CYCLE_LENGTH) > (before_cycle / CYCLE_LENGTH):
		has_reward = true
		_pending_show_uid = _dispatch_streak_chest()

	_revive_anim = {"kind": "backfill", "pre_cycle": before_cycle, "gained": add}

	_record_history_range(previous_jdn + 1, today_jdn)
	_data.last_checkin_date = today

	_data.last_checkin_minute = _now_minute_of_day()

	_data.pending_win_checkin_date = ""
	if _data.current_streak > _data.best_streak:
		_data.best_streak = _data.current_streak
	_save_data()

	DataSyncManager.request_sync("streak_revive")

	Tracker.track_spark_streak(_data.current_streak, _data.best_streak)

	var result := {
		"streak": _data.current_streak,
		"best_streak": _data.best_streak,
		"has_reward": has_reward,
		"missed_days": missed,
	}
	streak_updated.emit(_data)
	return result


## 放弃补签仍结算今天的胜利，按普通打卡规则重新开始连续天数。
func give_up_revive() -> Dictionary:
	return do_checkin()


func get_revive_anim() -> Dictionary:
	return _revive_anim


func get_last_checkin_minute() -> int:
	if _data.last_checkin_date != _today_str():
		return -1
	var m: int = _data.last_checkin_minute
	if m < 0 or m > 1439:
		return -1
	return m


# ================= 对外数据 =================
## 当前打卡数据（UI 只读，不要直接改）
func get_data() -> StreakData:
	return _data


func get_display_streak() -> int:
	return 0 if is_broken() else _data.current_streak


func get_history_month(year: int, month: int) -> Array[bool]:
	return StreakHistory.build_month(_data.history_ranges, year, month)


func get_today_date() -> Dictionary:
	return StreakHistory.jdn_to_date(_today_jdn())


func get_history_month_range() -> Dictionary:
	var today: Dictionary = StreakHistory.jdn_to_date(_today_jdn())
	return StreakHistory.month_range(_data.history_ranges, today["year"], today["month"])


func get_display_reward_cycle() -> int:
	return 0 if is_broken() else maxi(0, _data.reward_cycle_day)


func get_week_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var start_wd: int = (
		_data.streak_start_weekday if _data.streak_start_weekday >= 0 else _today_weekday()
	)
	var filled: int = 0

	if not is_broken() and _data.reward_cycle_day > 0:
		var mod: int = _data.reward_cycle_day % CYCLE_LENGTH
		if mod == 0:
			if not can_checkin_today():
				filled = CYCLE_LENGTH
		else:
			filled = mod
	for i: int in range(CYCLE_LENGTH):
		var wd: int = (start_wd + i) % 7
		var checked: bool = i < filled
		slots.append({"weekday": wd, "checked": checked})
	return slots


# ================= 奖励展示 =================
## 是否有打卡待演（uid >= 0）；uid > 0 才代表真有奖励
func has_pending_show() -> bool:
	return _pending_show_uid >= 0


## 待展示的奖励 uid（-1 = 无）
func get_pending_show_uid() -> int:
	return _pending_show_uid


## 把奖励弹给玩家（uid > 0 才真弹）；参数 _double 目前没有用到
func claim_reward(_double: bool = false) -> Dictionary:
	if _pending_show_uid < 0:
		return {}
	if _pending_show_uid > 0:
		AwardManager.show_award(_pending_show_uid)
	streak_updated.emit(_data)
	return {}


func consume_pending_show() -> void:
	_pending_show_uid = -1
	_revive_anim = {}


func reset() -> void:
	_data = StreakData.new()
	_pending_show_uid = -1
	_revive_anim = {}
	_pending_switch_eligible = false
	_save_data()
	streak_updated.emit(_data)


func cloud_save_id() -> String:
	return "streak"


func export_cloud_data() -> Dictionary:
	return {
		"current_streak": _data.current_streak,
		"best_streak": _data.best_streak,
		"last_checkin_date": _data.last_checkin_date,
		"last_checkin_minute": _data.last_checkin_minute,
		"streak_start_weekday": _data.streak_start_weekday,
		"reward_cycle_day": _data.reward_cycle_day,
	}


## 玩家明确选云档时采用云进度，否则按日期和最大计数合并，并补全本地历史覆盖。
func merge_cloud_data(cloud_data: Dictionary, ctx: MergeContext = null) -> void:
	if cloud_data.is_empty():
		return

	if ctx != null and ctx.by_player_choice:
		if not ctx.use_cloud:
			return
		_data.current_streak = int(cloud_data.get("current_streak", _data.current_streak))
		_data.best_streak = int(cloud_data.get("best_streak", _data.best_streak))
		_data.last_checkin_date = str(cloud_data.get("last_checkin_date", _data.last_checkin_date))
		_data.last_checkin_minute = int(
			cloud_data.get("last_checkin_minute", _data.last_checkin_minute)
		)
		_data.streak_start_weekday = int(
			cloud_data.get("streak_start_weekday", _data.streak_start_weekday)
		)
		_data.reward_cycle_day = int(cloud_data.get("reward_cycle_day", _data.reward_cycle_day))
		_realign_start_weekday()
		_ensure_history_covers_current()
		_save_data()

		streak_updated.emit(_data)
		return
	var local: Dictionary = {
		"current_streak": _data.current_streak,
		"best_streak": _data.best_streak,
		"last_checkin_date": _data.last_checkin_date,
		"last_checkin_minute": _data.last_checkin_minute,
		"streak_start_weekday": _data.streak_start_weekday,
		"reward_cycle_day": _data.reward_cycle_day,
	}
	var cloud_date: String = str(cloud_data.get("last_checkin_date", ""))
	var local_jdn: int = (
		_date_str_to_jdn(_data.last_checkin_date) if not _data.last_checkin_date.is_empty() else 0
	)
	var cloud_jdn: int = _date_str_to_jdn(cloud_date) if not cloud_date.is_empty() else 0
	var merged: Dictionary = StreakData.resolve_merge(local, cloud_data, local_jdn, cloud_jdn)
	_data.current_streak = int(merged["current_streak"])
	_data.best_streak = int(merged["best_streak"])
	_data.last_checkin_date = str(merged["last_checkin_date"])

	_data.last_checkin_minute = int(merged["last_checkin_minute"])
	_data.streak_start_weekday = int(merged["streak_start_weekday"])
	_data.reward_cycle_day = int(merged["reward_cycle_day"])
	_ensure_history_covers_current()
	_save_data()
	streak_updated.emit(_data)


func is_broken() -> bool:
	if _data.last_checkin_date.is_empty():
		return false
	return _today_jdn() - _date_str_to_jdn(_data.last_checkin_date) > 1


func missed_days() -> int:
	if _data.last_checkin_date.is_empty():
		return 0
	return maxi(0, _today_jdn() - _date_str_to_jdn(_data.last_checkin_date) - 1)


## 冷启动遇到未完成的补签选择时，将当时胜利记为新一轮第 1 天，避免胜利丢失。
func _resolve_pending_win_checkin() -> void:
	var victory_date: String = _data.pending_win_checkin_date
	if victory_date == "":
		return
	_data.pending_win_checkin_date = ""

	_data.current_streak = 1
	_data.reward_cycle_day = 1
	_data.last_checkin_date = victory_date
	var victory_jdn: int = StreakData.history_date_to_jdn(victory_date)
	_record_history_range(victory_jdn, victory_jdn)
	var weekday: int = _weekday_of_date(victory_date)
	_data.streak_start_weekday = weekday if weekday >= 0 else _today_weekday()
	if _data.best_streak < 1:
		_data.best_streak = 1
	_save_data()

	Tracker.track_spark_streak(_data.current_streak, _data.best_streak)


func _record_history_range(start_jdn: int, end_jdn: int) -> void:
	_data.history_ranges = StreakHistory.add_range(
		_data.history_ranges, start_jdn, end_jdn, end_jdn
	)


func _realign_start_weekday() -> bool:
	var last_jdn: int = StreakData.history_date_to_jdn(_data.last_checkin_date)
	var derived: int = StreakData.derive_start_weekday(
		last_jdn, _data.reward_cycle_day, _data.streak_start_weekday
	)
	if derived == _data.streak_start_weekday:
		return false
	_data.streak_start_weekday = derived
	return true


func _ensure_history_covers_current() -> bool:
	var last_jdn: int = StreakData.history_date_to_jdn(_data.last_checkin_date)
	var covered: Array = StreakHistory.ensure_covers_current(
		_data.history_ranges, last_jdn, _data.current_streak
	)
	if covered == _data.history_ranges:
		return false
	_data.history_ranges = covered
	return true


# ================= 奖励构建 =================
## 奖励字典的副本（目前没有调用方）
func _build_reward() -> Dictionary:
	return StreakData.REWARD_BASE.duplicate()


## 把奖励基数转成 AwardItem 列表，数量为 0 的道具跳过
func _build_reward_items() -> Array:
	var items: Array = []
	for kind: String in StreakData.REWARD_BASE:
		var count: int = int(StreakData.REWARD_BASE[kind])
		if count > 0:
			items.append(AwardItem.make(kind, count))
	return items


func _dispatch_streak_chest() -> int:
	var items: Array = _build_reward_items()
	return (
		AwardManager
		. dispatch(
			items,
			AwardManager.DisplayType.STREAK_GIFT,
			Tracker.PropSource.STREAK_CHEST,
			Tracker.PropSource.STREAK_REWARD_AD,
		)
	)


func _save_data() -> void:
	var config: ConfigFile = ConfigFile.new()
	var serialized: Dictionary = _data.to_dict()
	for key: String in serialized:
		config.set_value("streak", key, serialized[key])
	if not _store.save_config(config):
		push_error("StreakManager: 打卡存档保存失败，旧文件保持不变")


func _load_data() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var config: ConfigFile = _store.load_config()
	if config == null:
		push_error("StreakManager: 打卡存档读取失败")
		return false
	if not config.has_section("streak"):
		return false
	var serialized: Dictionary = {}
	var keys: PackedStringArray = config.get_section_keys("streak")
	for key: String in keys:
		serialized[key] = config.get_value("streak", key)
	_data = StreakData.from_dict(serialized)
	_ensure_history_covers_current()
	var weekday_changed: bool = _realign_start_weekday()
	return weekday_changed or serialized.get("history_ranges", []) != _data.history_ranges


func cheat_capture_history_state() -> Dictionary:
	if OS.has_feature("rel"):
		return {}
	return {
		"data": _data.to_dict(),
		"pending_uid": _pending_show_uid,
		"revive_anim": _revive_anim.duplicate(true),
		"switch_eligible": _pending_switch_eligible,
		"last_seen_jdn": _last_seen_jdn
	}


func cheat_history_today() -> String:
	return _today_str()


func cheat_apply_history_fixture(serialized: Dictionary, preserve_ab_state: bool = true) -> bool:
	if OS.has_feature("rel"):
		return false
	var fixture: Dictionary = (
		cheat_preserve_local_ab_fields(serialized) if preserve_ab_state else serialized
	)
	return _cheat_apply_state(fixture, not preserve_ab_state)


func _cheat_can_prepare_state() -> bool:
	if OS.has_feature("rel"):
		return false
	if has_pending_show() or has_pending_revive_decision():
		push_warning("[StreakCheat] 请先完成当前打卡、补签或领奖流程")
		return false
	return true


func _cheat_apply_state(fixture: Dictionary, clear_switch_eligible: bool = false) -> bool:
	if not _cheat_can_prepare_state():
		return false
	var config: ConfigFile = ConfigFile.new()
	var keys: Array = fixture.keys()
	for key: String in keys:
		config.set_value("streak", key, fixture[key])
	if not _store.save_config(config):
		push_error("StreakManager: 造数保存失败，内存及旧档保持不变")
		return false
	_data = StreakData.from_dict(fixture)
	_pending_show_uid = -1
	_revive_anim = {}
	if clear_switch_eligible:
		_pending_switch_eligible = false
	_last_seen_jdn = _today_jdn()
	streak_updated.emit(_data)
	return true


func cheat_preserve_local_ab_fields(serialized: Dictionary) -> Dictionary:
	if OS.has_feature("rel"):
		return {}
	var result: Dictionary = serialized.duplicate(true)
	var current: Dictionary = _data.to_dict()
	var fields: Array[String] = [
		"last_group", "pending_switch_page", "icon_group", "icon_group_date"
	]
	for field: String in fields:
		result[field] = current[field]
	return result


func cheat_reload_history_fixture() -> bool:
	if not _cheat_can_prepare_state():
		return false
	var history_changed: bool = _load_data()
	if history_changed:
		_save_data()
	streak_updated.emit(_data)
	return true


func _cheat_continuous_fixture(days: int, last_date: String) -> Dictionary:
	var fixture: Dictionary = _data.to_dict()
	var last_jdn: int = StreakData.history_date_to_jdn(last_date)
	fixture["current_streak"] = days
	fixture["reward_cycle_day"] = days
	fixture["best_streak"] = maxi(_data.best_streak, days)
	fixture["last_checkin_date"] = last_date
	fixture["last_checkin_minute"] = -1
	fixture["pending_win_checkin_date"] = ""
	fixture["streak_start_weekday"] = posmod(last_jdn + 1 - (days - 1), 7)
	fixture["history_ranges"] = StreakHistory.ensure_covers_current([], last_jdn, days)
	return fixture


func cheat_setup_six_days() -> bool:
	var last_date: String = _date_offset_str(-1)
	return _cheat_apply_state(_cheat_continuous_fixture(6, last_date))


func cheat_set_days(days: int = 1) -> bool:
	days = maxi(1, days)
	return _cheat_apply_state(_cheat_continuous_fixture(days, _today_str()))


func cheat_clear_today() -> bool:
	if not _cheat_can_prepare_state():
		return false
	var today: String = _today_str()
	if _data.last_checkin_date != today:
		push_warning("[StreakCheat] 今天本来就没打卡,clear no-op")
		return true
	var fixture: Dictionary = _data.to_dict()
	var today_jdn: int = StreakData.history_date_to_jdn(today)
	var retained_ranges: Array = []
	for interval: Array in _data.history_ranges:
		if interval[0] > today_jdn or interval[1] < today_jdn:
			retained_ranges.append(interval.duplicate())
			continue
		if interval[0] < today_jdn:
			retained_ranges.append([interval[0], today_jdn - 1])
		if interval[1] > today_jdn:
			retained_ranges.append([today_jdn + 1, interval[1]])
	var remaining_days: int = maxi(0, _data.current_streak - 1)
	fixture["last_checkin_date"] = _date_offset_str_from(today, -1)
	fixture["last_checkin_minute"] = -1
	fixture["pending_win_checkin_date"] = ""
	fixture["current_streak"] = remaining_days
	fixture["reward_cycle_day"] = maxi(0, _data.reward_cycle_day - 1)
	fixture["history_ranges"] = StreakHistory.ensure_covers_current(
		retained_ranges, today_jdn - 1, remaining_days
	)
	if remaining_days == 0:
		fixture["streak_start_weekday"] = -1
	return _cheat_apply_state(fixture)


func cheat_checkin_at(minute_of_day: int) -> Dictionary:
	if not _cheat_can_prepare_state():
		return {}
	var checkin_minute: int = clampi(minute_of_day, 0, 1439)
	if not can_checkin_today() and not cheat_clear_today():
		return {}
	if not can_checkin_today():
		push_warning("[StreakCheat] 当前日期早于上次打卡日，不能执行指定时刻打卡")
		return {}
	var result: Dictionary = do_checkin()

	_data.last_checkin_minute = checkin_minute
	_save_data()
	streak_updated.emit(_data)
	return result


func cheat_skip_day() -> bool:
	if not _cheat_can_prepare_state():
		return false
	if _data.last_checkin_date.is_empty():
		push_warning("[StreakCheat] last_checkin_date 空,跳过 skip")
		return true
	var fixture: Dictionary = _data.to_dict()
	var shifted_ranges: Array = []
	for interval: Array in _data.history_ranges:
		shifted_ranges.append([interval[0] - 1, interval[1] - 1])
	var last_date: String = _date_offset_str_from(_data.last_checkin_date, -1)
	var last_jdn: int = StreakData.history_date_to_jdn(last_date)
	fixture["last_checkin_date"] = last_date
	fixture["last_checkin_minute"] = -1
	fixture["pending_win_checkin_date"] = ""
	fixture["history_ranges"] = StreakHistory.ensure_covers_current(
		shifted_ranges, last_jdn, _data.current_streak
	)
	if _data.streak_start_weekday >= 0:
		fixture["streak_start_weekday"] = posmod(_data.streak_start_weekday - 1, 7)
	fixture["icon_group"] = -1
	fixture["icon_group_date"] = ""
	return _cheat_apply_state(fixture)


func cheat_setup_broken(missed: int = 1, streak: int = 5) -> bool:
	missed = maxi(1, missed)
	streak = maxi(2, streak)
	var last_date: String = _date_offset_str(-(missed + 1))
	return _cheat_apply_state(_cheat_continuous_fixture(streak, last_date))


func _date_offset_str(days: int) -> String:
	var local_date: Dictionary = Time.get_date_dict_from_system(false)
	return _date_offset_str_from(
		"%d-%02d-%02d" % [local_date.year, local_date.month, local_date.day], days
	)


## 把日期串偏移若干天：先转 Unix 时间戳，加减天数后再格式化
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


func _today_str() -> String:
	var local_date: Dictionary = Time.get_date_dict_from_system(false)
	return "%d-%02d-%02d" % [local_date.year, local_date.month, local_date.day]


func _now_minute_of_day() -> int:
	var local_time: Dictionary = Time.get_time_dict_from_system(false)
	return int(local_time["hour"]) * 60 + int(local_time["minute"])


func _today_weekday() -> int:
	var local_date: Dictionary = Time.get_date_dict_from_system(false)
	return local_date.weekday as int


static func _weekday_of_date(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return -1
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
	return int(Time.get_datetime_dict_from_unix_time(unix).weekday)


func _today_jdn() -> int:
	var local_date: Dictionary = Time.get_date_dict_from_system(false)
	return _local_date_to_jdn(local_date.year, local_date.month, local_date.day)


## 日期串 → 儒略日序号（格式不对时返回 0）
static func _date_str_to_jdn(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return 0
	return _local_date_to_jdn(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())


## 公历 → 儒略日序号的经典公式（纯整数运算）
static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
