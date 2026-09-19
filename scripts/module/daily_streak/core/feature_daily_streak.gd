# 连续打卡（每日连胜）的核心逻辑，注册为自动加载单例 StreakManager
# 负责打卡判定、连续天数累计与断签清零、每 7 天一份宝箱奖励，数据存在 user://streak.cfg
extends Node

const SAVE_PATH := "user://streak.cfg" # 存档路径（ConfigFile 格式，只有 [streak] 一段）
const CYCLE_LENGTH: int = 7 # 奖励周期长度：每满 7 天发一次宝箱

# ---- 信号 ----
signal streak_updated(data: StreakData) # 打卡数据有变化（打卡 / 断签 / 重置 / 领奖），UI 据此重刷
signal checkin_completed(result: Dictionary) # 本次打卡完成，result 见 do_checkin 的返回值
signal reward_claimed(reward: Dictionary) # 领奖信号（目前没有地方 emit，预留给 UI）

# ---- 运行时状态（_data 会被整份写进存档） ----
var _data: StreakData = StreakData.new() # 内存里的打卡数据，读写存档都以它为准

var _pending_show_uid: int = -1 # 待展示奖励 uid：-1 无 / 0 只打了卡没奖励 / >0 有奖励待展示

var _pending_switch_eligible: bool = false # 本次启动是否允许弹切组说明页；消费后置 false

var _last_seen_jdn: int = 0 # 上次看到的「今天」的儒略日序号，用于跨天检测


# ================= 生命周期与跨天检测 =================
# 读存档、补一次断签检查，并挂 1 秒心跳来发现跨天
func _ready() -> void:
	_load_data()

	# 启动时先看存档里有没有上次留下的切组说明页
	_pending_switch_eligible = _data.pending_switch_page > 0
	_check_continuity()
	# 账号数据被重置时一起清空打卡数据
	GameState.all_data_reset.connect(reset)

	# 挂一个 1 秒轮询的 Timer：跨天时立刻重算连续天数并发信号
	_last_seen_jdn = _today_jdn()
	var watch := Timer.new()
	watch.wait_time = 1.0
	watch.one_shot = false
	watch.autostart = true
	watch.timeout.connect(_on_day_watch_tick)
	add_child(watch)


# 心跳：日期没变直接返回，变了才做断签检查并发 streak_updated
func _on_day_watch_tick() -> void:
	var today_jdn: int = _today_jdn()
	if today_jdn == _last_seen_jdn:
		return
	_last_seen_jdn = today_jdn
	_check_continuity()
	streak_updated.emit(_data)


# ================= AB 实验开关 =================
# 当前分组编号：0 控制 / 1 基础 / 2 仅挑战 / 3 无奖励 / 4 不点亮
func get_ab_group() -> int:
	return ABTestManager.daily_streak.value()


# 实验是否开启（非控制组）
func is_enabled() -> bool:
	return ABTestManager.daily_streak.is_enabled()


# 本分组是否发第 7 天宝箱
func has_reward() -> bool:
	return ABTestManager.daily_streak.has_reward()


# 本分组是否跳过「首次点亮」那一屏
func should_skip_lit() -> bool:
	return ABTestManager.daily_streak.is_skip_lit()


# 功能对玩家是否可见：实验开启且新手引导已完成
func is_unlocked() -> bool:
	if not is_enabled():
		return false
	return GameState.is_tutorial_done()


# ================= 分组切换说明页 =================
# 启动染色后由主页调用：比对存档里的旧分组与当前分组，映射出要弹的说明页
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


# 分组变化 → 说明页编号的映射；返回 0 表示不用弹
func _map_switch_page(old_group: int, new_group: int) -> int:
	if (old_group == 1 or old_group == 2 or old_group == 4) and (new_group == 0 or new_group == 3):
		return 1
	if old_group == 3 and new_group == 0:
		return 2
	if old_group == 3 and (new_group == 1 or new_group == 2 or new_group == 4):
		return 3
	return 0


# 待弹的说明页编号（0 = 不弹），只有本次启动有资格时才返回
func get_pending_switch_page() -> int:
	return _data.pending_switch_page if _pending_switch_eligible else 0


# 消费掉待弹说明页并写存档（主页弹完就调）
func consume_pending_switch() -> void:
	_data.pending_switch_page = 0
	_pending_switch_eligible = false
	_save_data()


# 补发切组礼包：直接进背包（DIRECT 展示），不走宝箱动画
func grant_switch_gift() -> void:
	var items: Array = _build_reward_items()
	if items.is_empty():
		return
	AwardManager.dispatch(items, AwardManager.DisplayType.DIRECT, Tracker.PropSource.SWITCH_GROUP)


# ================= 打卡 =================
# 今天还能不能打卡：最近打卡日期不是今天就还能打
func can_checkin_today() -> bool:
	return _data.last_checkin_date != _today_str()


# 哪种胜利算打卡：默认主线与每日挑战都算，「仅挑战」档只算每日挑战
func is_win_qualifies(source: StringName) -> bool:
	if not is_enabled():
		return false
	if ABTestManager.daily_streak.is_challenge_only():
		return source == &"challenge"
	return source == &"main" or source == &"challenge"


# 游戏胜利时的入口：未解锁 / 今天已打卡 / 胜利类型不符都直接返回，否则打卡
func notify_win(source: StringName) -> void:
	if not is_unlocked():
		return
	if not can_checkin_today():
		return
	if not is_win_qualifies(source):
		return
	do_checkin()


# 真正打卡：记日期、连续天数与周期天数各 +1，满 7 天发奖励，然后写存档并发信号
func do_checkin() -> Dictionary:
	# 先落日期：同一天再调用 can_checkin_today 就会返回 false
	var today := _today_str()
	_data.last_checkin_date = today

	# 连续天数与周期内天数都 +1；周期天数决定第几天开箱
	_data.current_streak += 1
	_data.reward_cycle_day += 1

	# 刷新历史最佳
	if _data.current_streak > _data.best_streak:
		_data.best_streak = _data.current_streak

	# 本轮第一天：记下今天星期几，7 个格子据此排列
	if _data.streak_start_weekday < 0:
		_data.streak_start_weekday = _today_weekday()

	# 默认「只有打卡、没有奖励」；下面真有奖励时会覆盖成真实 uid
	_pending_show_uid = 0

	var has_reward := false
	# 满 7 天且本分组发奖励时，立刻把奖励派发掉（奖励页由打卡页负责演）
	if _data.reward_cycle_day > 0 and _data.reward_cycle_day % CYCLE_LENGTH == 0:
		if ABTestManager.daily_streak.has_reward():
			has_reward = true

			# 把固定奖励基数转成 AwardItem 列表并派发，记下待展示的 uid
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

	# 先写存档，再上报埋点、发信号
	_save_data()

	# 上报连续天数埋点
	Tracker.track_spark_streak(_data.current_streak, _data.best_streak)

	# 返回给调用方（游戏页 / 打卡页）的本次结果
	var result := {
		"streak": _data.current_streak,
		"best_streak": _data.best_streak,
		"has_reward": has_reward,
		"is_new_streak": _data.current_streak == 1,
	}
	checkin_completed.emit(result)
	streak_updated.emit(_data)
	return result


# ================= 对外数据 =================
# 当前打卡数据（UI 只读，不要直接改）
func get_data() -> StreakData:
	return _data


# 7 个格子的展示数据，每项是 {weekday: 0~6, checked: bool}
# 点亮格数 = reward_cycle_day % 7；刚好满 7 天且今天打过卡时 7 格全亮
func get_week_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	# 本轮还没开始时以今天为起点（只影响显示，不写存档）
	var start_wd: int = (
		_data.streak_start_weekday if _data.streak_start_weekday >= 0 else _today_weekday()
	)
	# 点亮格数：周期天数为 0 时是 0；模 7 为 0 且今天已打卡时是满格
	var filled: int = 0
	if _data.reward_cycle_day > 0:
		var mod: int = _data.reward_cycle_day % CYCLE_LENGTH
		if mod == 0:
			if _data.last_checkin_date == _today_str():
				filled = CYCLE_LENGTH
		else:
			filled = mod
	# 从起点星期开始依次排 7 格，前 filled 格点亮
	for i: int in range(CYCLE_LENGTH):
		var wd: int = (start_wd + i) % 7
		var checked: bool = i < filled
		slots.append({"weekday": wd, "checked": checked})
	return slots


# ================= 奖励展示 =================
# 是否有打卡待演（uid >= 0）；uid > 0 才代表真有奖励
func has_pending_show() -> bool:
	return _pending_show_uid >= 0


# 待展示的奖励 uid（-1 = 无）
func get_pending_show_uid() -> int:
	return _pending_show_uid


# 把奖励弹给玩家（uid > 0 才真弹）；参数 _double 目前没有用到
func claim_reward(_double: bool = false) -> Dictionary:
	if _pending_show_uid < 0:
		return {}
	if _pending_show_uid > 0:
		AwardManager.show_award(_pending_show_uid)
	streak_updated.emit(_data)
	return {}


# 清掉待展示标记（打卡页演完动画后调用）
func consume_pending_show() -> void:
	_pending_show_uid = -1


# ================= 重置与断签 =================
# 整份重置；账号数据被清空时调用，并写存档、发信号
func reset() -> void:
	_data = StreakData.new()
	_pending_show_uid = -1
	_pending_switch_eligible = false
	_save_data()
	streak_updated.emit(_data)


# 断签检查：距上次打卡超过 1 天就清零（连续天数、周期天数、本轮起点、待展示奖励）
func _check_continuity() -> void:
	# 从没打过卡，不用检查
	if _data.last_checkin_date.is_empty():
		return
	var last_jdn: int = _date_str_to_jdn(_data.last_checkin_date)
	var today_jdn: int = _today_jdn()
	var diff: int = today_jdn - last_jdn
	# 差 0 / 1 天都算连续；超过 1 天说明中间断了
	if diff > 1:
		_data.current_streak = 0
		_data.reward_cycle_day = 0
		_data.streak_start_weekday = -1

		_pending_show_uid = -1
		_save_data()


# ================= 奖励构建 =================
# 奖励字典的副本（目前没有调用方）
func _build_reward() -> Dictionary:
	return StreakData.REWARD_BASE.duplicate()


# 把奖励基数转成 AwardItem 列表，数量为 0 的道具跳过
func _build_reward_items() -> Array:
	var items: Array = []
	for kind: String in StreakData.REWARD_BASE:
		var count: int = int(StreakData.REWARD_BASE[kind])
		if count > 0:
			items.append(AwardItem.make(kind, count))
	return items


# ================= 存档读写 =================
# 整份写进 streak.cfg 的 [streak] 段
func _save_data() -> void:
	var cfg := ConfigFile.new()
	var d: Dictionary = _data.to_dict()
	for k: String in d:
		cfg.set_value("streak", k, d[k])
	cfg.save(SAVE_PATH)


# 读 streak.cfg；文件不存在或读失败就保持默认数据
func _load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var d: Dictionary = {}
	for k: String in cfg.get_section_keys("streak"):
		d[k] = cfg.get_value("streak", k)
	_data = StreakData.from_dict(d)


# ================= 调试作弊接口（CheatBus 调用） =================
# 造出「已连续 6 天」的存档，方便测第 7 天开箱
func cheat_setup_six_days() -> void:
	_data.current_streak = 6
	_data.reward_cycle_day = 6
	_data.best_streak = max(_data.best_streak, 6)
	_data.last_checkin_date = _date_offset_str(-1)
	_data.streak_start_weekday = (_today_weekday() - 6 + 7) % 7
	_pending_show_uid = -1
	_save_data()
	streak_updated.emit(_data)


# 撤回今天的打卡（日期改成昨天、天数各减 1），用于反复测打卡流程
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


# 把上次打卡日期再往前挪一天，用来触发断签
func cheat_skip_day() -> void:
	if _data.last_checkin_date.is_empty():
		push_warning("[StreakCheat] last_checkin_date 空,跳过 skip")
		return
	_data.last_checkin_date = _date_offset_str_from(_data.last_checkin_date, -1)
	_check_continuity()
	streak_updated.emit(_data)


# ================= 日期工具（纯 static，不碰状态） =================
# 今天往前 / 后偏移若干天的日期串
static func _date_offset_str(days: int) -> String:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return _date_offset_str_from("%d-%02d-%02d" % [dt.year, dt.month, dt.day], days)


# 把日期串偏移若干天：先转 Unix 时间戳，加减天数后再格式化
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


# 今天的日期串 yyyy-mm-dd（本地时间）
static func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


# 今天是星期几（0 = 周日）
static func _today_weekday() -> int:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return dt.weekday as int


# 今天的儒略日序号，用于比较两个日期差几天
static func _today_jdn() -> int:
	var dt: Dictionary = Time.get_date_dict_from_system(false)
	return _local_date_to_jdn(dt.year, dt.month, dt.day)


# 日期串 → 儒略日序号（格式不对时返回 0）
static func _date_str_to_jdn(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return 0
	return _local_date_to_jdn(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())


# 公历 → 儒略日序号的经典公式（纯整数运算）
static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
