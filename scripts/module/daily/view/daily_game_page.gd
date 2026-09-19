# 每日挑战游戏页：每天按日期从题库里固定挑一道题，复用主线棋盘与道具，带 3 条命、计时和复活
class_name DailyGamePage
extends BaseGamePage

const SettingScene: PackedScene = preload("res://scripts/module/setting/ui/setting_page.tscn") # 设置页场景预加载（本脚本内没引用，疑似历史遗留）

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _date_label: Label = $Root/VBoxContainer/Header/DateLabel # 头部日期文案（部分实验档会隐藏）
@onready var _level_display_value: Label = $Root/VBoxContainer/Header/LevelDisplay/Value # 头部「月/日」数字显示
# 计时文字（@onready 与变量声明分两行写的那个）
@onready
var _timer_label: Label = $Root/VBoxContainer/CatHeartRow/TimeContainer/HBoxContainer/TimerCtrl/TimerLabel

# ---- 运行时状态 ----
var _start_unix: float = 0.0 # 计时起点（Unix 秒）；广告占用的时长之后会补掉
var _start_date: String = "" # 开局日期 yyyy-mm-dd，通关时写进存档
var _ad_show_unix: float = 0.0 # 广告开始播放的时刻，> 0 表示有一段广告时长待扣除

var _pending_show_auto_mark_popup: bool = false # 是否等棋盘出场动画播完再弹自动标叉弹窗

# 出场动画期间要锁住的头部按钮
@onready var _entry_locked_buttons: Array[Button] = [
	$Root/VBoxContainer/Header/SettingsBtn,
	$Root/VBoxContainer/Header/GearBtn,
]

var _entry_btn_lock_seq: int = 0 # 锁按钮的次数，只累加不做判断（排查动画重入用）

static var debug_day_override: int = -1 # 调试开关：强制把「今天」当成第 N 天，-1 = 关闭


# ================= 生命周期 =================
# 埋点用的游戏类型：每日挑战
func _game_type() -> String:
	return Tracker.GameType.DAILY


# 绑棋盘信号、建提示与策略浮层，并监听广告开关
func _ready() -> void:
	_refresh_hearts()
	_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
	_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
	_board_view.cell_drag_end.connect(_on_board_cell_drag_end)

	_board_view.cell_state_changed.connect(_on_board_changed_for_auto_complete)

	_board_view.cell_state_changed.connect(_on_cell_changed_for_auto_mark)

	_board_view.cell_state_changed.connect(_on_cell_changed_for_lock_x)
	# 提示浮层：拉高层级、接上连锁详情回调，并建策略浮层
	_hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
	_hint_overlay.layer = 10
	_build_strategy_overlay()
	UniKitManager.ad_closed.connect(_on_ad_closed)

	UniKitManager.ad_shown.connect(_on_ad_shown_for_timer)

	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)


# 每次进页面：挑今天的题、铺棋盘、起计时，并处理开屏广告与自动标叉弹窗
func on_show(params: Dictionary = {}) -> void:
	Tracker.set_active_game_type(Tracker.GameType.DAILY)

	# 开局先摇分组，再按分组决定自动标叉的默认开关
	ABTestManager.dye_at_game_start()
	GameState.set_saved_game_auto_mark(ABTestManager.game_auto_mark.value())

	# 先算好要不要弹自动标叉弹窗，等棋盘出场动画播完再弹
	_pending_show_auto_mark_popup = _should_show_auto_mark_popup()

	# 把当前主线关卡号塞进参数，交给基类铺棋盘
	params = params.duplicate()
	params["level_index"] = GameState.get_current_level()
	super.on_show(params)

	# 棋盘先藏起来，等出场动画结束再显示
	_board_view.visible = false

	# 记下今天的日期串：用来判断本局是续玩还是新开，也用来算今天的题号
	var dt_local: Dictionary = Time.get_date_dict_from_system()
	_start_date = (
		"%d-%02d-%02d"
		% [dt_local.get("year", 2026), dt_local.get("month", 1), dt_local.get("day", 1)]
	)

	# 判定本局埋点状态：重开 / 今天已开过局=续玩 / 新开（并换新的 game id）
	var _explicit_status: String = params.get("_tracker_status", "")
	if _explicit_status == Tracker.GameStatus.RESTART:
		_stat_status = Tracker.GameStatus.RESTART
	elif GameState.get_daily_started_date() == _start_date:
		_stat_status = Tracker.GameStatus.CONTINUE
	else:
		_stat_status = Tracker.GameStatus.NEW
		GameState.set_daily_started_date(_start_date)
		Tracker.new_game_id(Tracker.GameType.DAILY)
	_stat_start_ms = Time.get_ticks_msec()

	# 挂上作弊命令（调试用）
	if not CheatBus.command_issued.is_connected(_on_cheat_command):
		CheatBus.command_issued.connect(_on_cheat_command)

	# 每道题有 8 种等价变换（镜像 × 4 个旋转），题池乘 8 就是可用的总题量
	const TRANSFORM_COUNT: int = 8

	# 今天距基准日 2026-04-21 的天数，决定今天抽哪道题
	var day_offset: int
	if DailyGamePage.debug_day_override >= 0:
		day_offset = DailyGamePage.debug_day_override
		print("[DailyGame] debug day_offset=%d (override)" % day_offset)
	else:
		day_offset = max(
			0,
			(
				_local_date_to_jdn(
					dt_local.get("year", 2026), dt_local.get("month", 4), dt_local.get("day", 21)
				)
				- _local_date_to_jdn(2026, 4, 21)
			)
		)

	# 摇「每日挑战难度」分组，再按分组挑题库分区（尺寸 / 难度档 / 题库来源）
	ABTestManager.dye_at_game_start_dc()
	var current_lv: int = GameState.get_current_level()
	var pool: Array = []
	var sz: int
	var rank: int
	var tier: String = "N"
	# 实验组：池子大小与难度档由 dc_level 按等级和天数算出来
	if ABTestManager.dc_level.is_override_enabled():
		sz = ABTestManager.dc_level.get_pool_size(current_lv, day_offset)
		rank = ABTestManager.dc_level.get_pool_rank(current_lv, day_offset)
		if ABTestManager.dc_level.use_gc_bank(sz, day_offset):
			pool = BankData.get_gc_levels(sz, rank)
		else:
			pool = BankData.get_levels(sz, rank)
	else:
		# 控制组：按主线进度走固定分档（10×3 → 10×4 → 12 的 lkstyle N 档）
		if current_lv <= 100:
			pool = BankData.get_levels(10, 3)
			sz = 10
			rank = 3
		elif current_lv <= 200:
			pool = BankData.get_levels(10, 4)
			sz = 10
			rank = 4
		else:
			pool = BankData.get_lk_style_levels_by_tier(12, 4, "N")
			sz = 12
			rank = 4
			tier = "N"

	# 题库为空属于配置错误，直接报错退出
	if pool.is_empty():
		push_error("DailyGamePage: 无可用关卡（current_lv=%d）" % current_lv)
		return

	# 把「题池 × 8 种等价变换」拉成一条虚拟时间轴：同一天永远取到同一题
	var pool_size: int = pool.size()
	var total_virtual: int = pool_size * TRANSFORM_COUNT
	var virtual_idx: int = day_offset % total_virtual
	var transform: int = virtual_idx / pool_size
	var entry_idx: int = virtual_idx % pool_size

	# 按虚拟下标取题；题面不合法就往后顺一格，跳过脏数据
	var entry: Dictionary = {}
	var sol_1d: Array = []
	var int_regions: Array = []
	var attempts: int = 0
	while attempts < total_virtual:
		entry = pool[entry_idx]
		sol_1d = []
		for v in entry.get("solution", []):
			sol_1d.append(int(v))
		var raw_regions: Array = entry.get("regionMap", [])
		int_regions = []
		for row_arr: Array in raw_regions:
			var int_row: Array = []
			for v in row_arr:
				int_row.append(int(v))
			int_regions.append(int_row)
		# 变换 0 是原题，另外 7 种是镜像/旋转出来的等价题面
		if transform > 0:
			var transformed: Array = LevelData.apply_transform(int_regions, sol_1d, sz, transform)
			int_regions = transformed[0]
			sol_1d = transformed[1]
		if QueendokuCore.validate_solution_entry(
			{"regionMap": int_regions, "solution": sol_1d}, sz
		):
			break
		push_error(
			(
				"DailyGamePage: invalid solution day_offset=%d virtual_idx=%d transform=%d entry_idx=%d, advancing"
				% [day_offset, virtual_idx, transform, entry_idx]
			)
		)
		virtual_idx = (virtual_idx + 1) % total_virtual
		transform = virtual_idx / pool_size
		entry_idx = virtual_idx % pool_size
		attempts += 1
	# 整池都不合法时容错：沿用最后一次读到的题，不再死循环
	if attempts >= total_virtual:
		push_error("DailyGamePage: 池内所有题目都不合法 sz=%d rank=%d, 容错沿用最后一次 entry" % [sz, rank])

	# R1~R5 五层提示策略的步数也来自题库记录
	_strategy_steps[0] = int(entry.get("r1", 0))
	_strategy_steps[1] = int(entry.get("r2", 0))
	_strategy_steps[2] = int(entry.get("r3", 0))
	_strategy_steps[3] = int(entry.get("r4", 0))
	_strategy_steps[4] = int(entry.get("r5", 0))

	# 正式包（rel 特性）里藏掉策略按钮
	if _strategy_btn != null:
		_strategy_btn.visible = not OS.has_feature("rel")

	# 把一维解（每行一个列号）还原成棋盘用的二维布尔表
	var sol_2d: Array = []
	for r: int in range(sz):
		var row: Array = []
		row.resize(sz)
		row.fill(false)
		if r < sol_1d.size():
			row[sol_1d[r]] = true
		sol_2d.append(row)

	# 本局关卡配置：尺寸 / 难度 / 题库来源 / 变换次数，埋点与结算都读它
	_level_config = {
		"size": sz,
		"rank": rank,
		"tier": tier,
		"is_daily": true,
		"seed": int(entry.get("seed", entry.get("id", 0))),
		"daily_index": virtual_idx,
		"daily_transform": transform,
		"bank_source": _get_dc_bank_source(current_lv, day_offset),
		"bank_idx": entry_idx + 1,
		"bank_transform": transform,
		"prefill_count": 0,
		"prefill_positions": [],
	}
	_puzzle = {"regions": int_regions, "solution": sol_2d}

	# 头部日期文案
	var dt: Dictionary = Time.get_datetime_dict_from_system()

	var month_str: String = tr("MONTH_ABBR_%d" % clampi(int(dt["month"]), 1, 12))
	_date_label.text = "%s.%d" % [month_str, dt["day"]]
	_level_display_value.text = "%02d/%02d" % [dt["month"], dt["day"]]
	_date_label.visible = not ABTestManager.combo_encourage.has_score_display()

	# 复位一局的运行时状态（血量、完成标记、提示数据等）
	_lives = 3
	_is_complete = false
	_wrong_guess_pending = false
	_hint_data = {}
	_last_placed_count = -1

	# 「猫手气」检测状态（基类定义）：下猫时刻、误标事件等
	_like_hand_state = {
		"in_game_sec": 0.0,
		"last_cat_sec": 0.0,
		"triggered_count": 0,
		"clock_paused": false,
		"has_seen_first_cat": false,
		"wrong_cat_events": [],
		"missed_cat_candidates": {},
		"missed_cat_prev": {},
	}
	# 从这一刻开始计时，并关掉可能还开着的胜负页面
	_start_unix = Time.get_unix_time_from_system()
	_timer_label.text = "00:00"
	_clock_timer.start()
	UIManager.hide_ui(UiName.DAILY_FAIL)
	UIManager.hide_ui(UiName.DAILY_WIN)
	_hint_overlay.visible = false

	_refresh_hearts()
	_sync_tools_from_state()

	# 等一帧让容器完成排版，再重排棋盘
	await get_tree().process_frame

	_relayout_board()

	var sz_v: int = _level_config["size"]

	# 棋盘出场期间禁掉入口按钮与棋盘输入，动画结束才放开
	_entry_anim_playing = true

	_lock_entry_buttons()

	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 重进页面时先停掉上一次的出场动画并断开回调，避免重复触发
	var board_intro := $Root as BoardContainerCell_01
	if _anim_player.is_playing():
		_anim_player.stop()
		if (
			board_intro != null
			and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
		):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)

	# 按 11 号尺寸重排目标强调与规则条的收起状态
	_apply_goal_emphasis_tracks(11)

	_apply_rule_swipe_collapse(11)

	# 播棋盘出场动画与音效，结束后回调 _on_appear_animation_finished
	_anim_player.play(_appear_anim_name())
	SoundManager.play(SoundManager.Kind.BOARD_ENTER)

	if (
		board_intro != null
		and not board_intro.animation_finished.is_connected(_on_appear_animation_finished)
	):
		board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)

	# 用「第几种变换」当配色种子，保证同一天的配色固定
	var color_seed: int = _level_config.get("daily_transform", 0)
	var color_map: Array[int] = LevelGenerator.compute_color_map_with_seed(
		sz, _puzzle["regions"], color_seed
	)

	if board_intro != null:
		board_intro.set_auto_trigger(false)
	# 铺棋盘：每日模式没有预置猫，第四个参数传空数组
	_board_view.setup(sz, _puzzle["regions"], color_map, [], true)
	if board_intro != null:
		board_intro.set_auto_trigger(true)

	if board_intro != null:
		board_intro.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame
	if board_intro != null:
		board_intro.play()

	_board_view.visible = true

	# 记录题面 id，用于统计重题
	var _pid: String = LevelData.compute_puzzle_id(sz, _puzzle["regions"])
	PuzzleSessionTracker.record(_pid)

	# 刷剩余数量与连击反馈，并接上连击信号
	_update_remaining()

	if _combo_feedback_view == null:
		_combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
	if _combo_feedback_view != null:
		_combo_feedback_view.reset(0)
	_connect_combo_signal()

	# 重置挂机提示
	_reset_idle_hint()

	# 上报开局埋点（qid / 旋转 / 状态 / 难度等）
	(
		Tracker
		. track_game_start(
			_build_qid(),
			Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
			_stat_status,
			Tracker.GameType.DAILY,
			_get_diffi(),
			GameState.get_current_level(),
			_level_config.get("rank", 0),
			_level_config.get("size", 0),
		)
	)

	# 按开局 / 重开 / 续玩选插屏广告位
	var ad_pos: String = Tracker.AdPos.NORMAL_START
	if _stat_status == Tracker.GameStatus.RESTART:
		ad_pos = Tracker.AdPos.NORMAL_RESTART
	elif _stat_status == Tracker.GameStatus.CONTINUE:
		ad_pos = Tracker.AdPos.NORMAL_CONTINUE

	# 要弹自动标叉弹窗时就不弹开屏插屏；广告占掉的时间稍后补回
	if not _pending_show_auto_mark_popup:
		var inter_elig: Dictionary = _eval_start_interstitial(params, ad_pos)
		if _try_show_start_interstitial(ad_pos, inter_elig):
			_ad_show_unix = Time.get_unix_time_from_system()
			_start_unix = _ad_show_unix
			_timer_label.text = "00:00"

	# 按条件显示首页横幅
	_show_banner_if_eligible("daily")


# 要不要弹自动标叉弹窗：道具广告模式 + 今天还没开 + 有免费额度或广告可看
func _should_show_auto_mark_popup() -> bool:
	# 不是「道具+广告」模式就不弹
	if not ABTestManager.game_auto_mark.is_prop_ad_mode():
		return false
	# 今天已经开过就不再问
	if GameState.is_daily_auto_mark_enabled_for_today():
		return false
	# 免费额度还没用掉就直接弹（不需要广告）
	if not GameState.is_daily_auto_mark_free_consumed():
		return true
	# 免费额度用完了：只有广告可看时才弹
	return UniKitManager.is_reward_valid("reward", Tracker.AdPos.AUTOX_REWARD)


# ================= 计时 =================
# 本局已用秒数（不含之后要补偿掉的广告时长）
func _get_elapsed_sec() -> int:
	return int(Time.get_unix_time_from_system() - _start_unix)


# 计时器心跳：只刷新文字
func _on_clock_timer_timeout() -> void:
	_refresh_timer_label()


# 按当前已用秒数刷新计时文字
func _refresh_timer_label() -> void:
	_apply_elapsed_to_label(_get_elapsed_sec())


# 把秒数写成 mm:ss；超过 1 小时改成 hh:mm:ss 并把字号调小
func _apply_elapsed_to_label(sec: int) -> void:
	if sec >= 3600:
		var h: int = sec / 3600
		var m: int = (sec % 3600) / 60
		var s: int = sec % 60
		_timer_label.text = "%02d:%02d:%02d" % [h, m, s]
		_timer_label.add_theme_font_size_override("font_size", 34)
	else:
		var m: int = sec / 60
		var s: int = sec % 60
		_timer_label.text = "%02d:%02d" % [m, s]
		_timer_label.add_theme_font_size_override("font_size", 50)


# 切到后台：故意留空，广告时长在回前台时统一补
func _on_application_focus_out() -> void:
	pass


# 回前台：先补掉广告占用的时长，再刷计时
func _on_application_focus_in() -> void:
	_compensate_ad_time()
	_refresh_timer_label()


# 记住激励视频开始播放的时刻，用来算要补多少秒
func _on_ad_shown_for_timer(placement_id: String) -> void:
	if placement_id == "reward":
		_ad_show_unix = Time.get_unix_time_from_system()


# 把广告占用的时长从计时起点往后推，让看广告不算进通关时间；补完清零
func _compensate_ad_time() -> void:
	if _ad_show_unix <= 0.0:
		return
	var ad_duration: float = Time.get_unix_time_from_system() - _ad_show_unix
	print("[DailyGame] ad compensated %.1fs" % ad_duration)
	_start_unix += ad_duration
	_ad_show_unix = 0.0


# 广告关闭后同样补一次时间
func _on_ad_closed(_placement_id: String) -> void:
	_compensate_ad_time()
	_refresh_timer_label()


# ================= 按钮与动画回调 =================
# 齿轮按钮 = 退出本局回主页（已结算就不再响应）
func _on_gear_btn_pressed() -> void:
	if _is_complete:
		return
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	_clock_timer.stop()
	UIManager.show_ui(UiName.HOME)
	UIManager.hide_ui(UiName.DAILY_GAME)


# 棋盘出场动画结束：放开入口按钮，需要的话弹自动标叉弹窗
func _on_appear_animation_finished() -> void:
	super._on_appear_animation_finished()
	_unlock_entry_buttons()
	if _pending_show_auto_mark_popup:
		_pending_show_auto_mark_popup = false
		UIManager.show_ui(UiName.DAILY_AUTO_MARK_POPUP)


# 把头部按钮设为不接收点击（出场动画期间防误触）
func _lock_entry_buttons() -> void:
	_entry_btn_lock_seq += 1
	for b in _entry_locked_buttons:
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE


# 恢复头部按钮的点击
func _unlock_entry_buttons() -> void:
	for b in _entry_locked_buttons:
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_STOP


# ================= 局内回调 / 重开 =================
# 重开本局：清连击与草稿、销掉横幅，先按「主动退出」结算再以 RESTART 重进
func _on_restart_requested() -> void:
	_combo_count = 0
	_combo_score = 0
	_hide_auto_complete_btn()
	_exit_draft_mode_and_clear()

	_destroy_banner()

	LevelOps.confirm_level_failed_daily(_build_game_end_params(Tracker.GameResult.QUIT))
	LevelOps.on_restart_click()
	on_show({"_tracker_status": Tracker.GameStatus.RESTART})


# 规则高亮只在「全关卡」实验档下播
func _on_rule_violated(rule: int) -> void:
	if not ABTestManager.rule_highlight.is_all_levels():
		return
	_play_rule_highlight(rule)


# 给三个道具按钮各配一个广告位（撤销没有专用位，用字符串兜底）
func _reward_pos_for(btn: Control) -> String:
	if btn == _tool_locate_btn:
		return Tracker.AdPos.PROPS_DAILY_LOCATE
	elif btn == _tool_undo_btn:
		return "props_daily_undo"
	return Tracker.AdPos.PROPS_DAILY_HINT


# ================= 失败 / 复活 =================
# 失败：停表清场、上报失败埋点，算出还差几只猫并弹失败页，接好复活回调
func _on_game_over() -> void:
	_hide_auto_complete_btn()
	if not _is_complete:
		GameState.on_game_finished()
	_exit_draft_mode_and_clear()
	_is_complete = true
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()
	Tracker.inc_stat("gamedie_count")

	# 失败结算时再摇一次分组
	ABTestManager.dye_at_game_fail_end()

	Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.FAIL))
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL4)
	# 数一数盘上已经放了多少只猫，反推还差几只
	var sz: int = _level_config.get("size", 12)
	var placed: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				placed += 1
	var remaining_cats: int = sz - placed
	# 弹失败页并把剩余猫数传进去；复活、广告开始两个信号接到本页
	var fail := (
		UIManager
		. show_ui(
			UiName.DAILY_FAIL,
			{
				"level_config": _level_config,
				"remaining_cats": remaining_cats,
			}
		)
	)
	if fail != null and not fail.revive_requested.is_connected(_on_revive_requested):
		fail.revive_requested.connect(_on_revive_requested)
	if fail != null and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
		fail.revive_ad_started.connect(_on_revive_ad_started)


# 广告开始播：先把棋盘上的猫全部退回待机，广告结束后再复原
func _on_revive_ad_started() -> void:
	_board_view.revive_all_cat_to_idle()


# 复活成功：遮掉失败页、加统计、恢复生命与计时，让本局继续
func _on_revive_requested() -> void:
	UIManager.hide_ui(UiName.DAILY_FAIL)
	_is_complete = false
	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "revive_count")
	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "rv_count")

	_lives = mini(_lives + ABTestManager.revive_life.get_lives_to_restore(), 3)
	_refresh_hearts()

	if ABTestManager.revive_life.get_lives_to_restore() >= 3:
		for slot: LifeSlot in [_heart1, _heart2, _heart3]:
			if slot != null:
				slot.play_revive()
	_clock_timer.start()

	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

	_board_view.revive_all_cat_to_idle()

	_show_banner_if_eligible("daily")


# ================= 通关 =================
# 通关：停表、按耗时折算超越百分比（开过自动标叉再加 5%），写存档并弹通关页
func _on_game_complete() -> void:
	_hide_auto_complete_btn()
	if not _is_complete:
		GameState.on_game_finished()

	_exit_draft_mode_and_clear(ABTestManager.draft_mode.keep_marks_on_manual_exit())
	_is_complete = true
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()

	# 结算耗时：先取本局秒数，再交给 DailyStats 折算成超越百分比
	var elapsed_sec: int = _get_elapsed_sec()
	_apply_elapsed_to_label(elapsed_sec)
	var rank: int = _level_config.get("rank", 4)
	_level_config["elapsed_sec"] = elapsed_sec
	var raw_percent: float = DailyStats.beat_percent(
		elapsed_sec, rank, _level_config.get("size", 12)
	)

	# 今天开过自动标叉的话，成绩额外加 5%（上限 99.9%）
	if (
		ABTestManager.game_auto_mark.is_prop_ad_mode()
		and GameState.is_daily_auto_mark_enabled_for_today()
	):
		raw_percent = minf(raw_percent + 5.0, 99.9)
	_level_config["beat_percent"] = raw_percent

	# 上报通关埋点，重播猫的出现动画并清理提示
	Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.WIN))

	SoundManager.stop(SoundManager.Kind.MARK_CAT)
	_board_view.replay_all_cat_appear()
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL5)
	_cleanup_hint()
	await get_tree().process_frame
	# 写存档：今天的完成日期、耗时、成绩（顺带刷新历史最佳）
	GameState.mark_daily_completed(_start_date, elapsed_sec, _level_config["beat_percent"])

	# 等主页 Toast 与连续打卡流程走完，再弹通关页
	var toast_was_shown: bool = await _play_win_toast_and_wait()
	_level_config["toast_was_shown"] = toast_was_shown
	var streak_consumed_appear_delay: bool = await _try_run_streak_flow_after_win(
		&"challenge", toast_was_shown
	)
	_level_config["skip_appear_delay"] = streak_consumed_appear_delay
	UIManager.show_ui(_win_ui_name(), {"level_config": _level_config, "board_view": _board_view})


# 本页对应的通关页 UI 名（每日挑战固定）
func _win_ui_name() -> StringName:
	return UiName.DAILY_WIN


# 打卡流程：先登记胜利，有待展示的奖励就打开打卡页并等它关闭；返回是否占用了出现延迟
func _try_run_streak_flow_after_win(source: StringName, skip_cat_appear: bool = false) -> bool:
	StreakManager.notify_win(source)
	if not StreakManager.has_pending_show():
		return false
	if not skip_cat_appear:
		await get_tree().create_timer(DailyWinPage.APPEAR_DELAY).timeout
	var streak_page: StreakPage

	# 第 1 天走「点亮」态，其余走结算态
	if StreakManager.get_data().current_streak == 1 and not StreakManager.should_skip_lit():
		streak_page = StreakPage.open_lit()
	else:
		streak_page = StreakPage.open_settle()
	# 等打卡页关掉再继续（通关页据此跳过出现延迟）
	while is_instance_valid(streak_page) and streak_page.visible:
		await streak_page.visibility_changed
	return true


# ================= 调试与埋点 =================
# 响应 CheatBus 的 win / lives 两条调试命令
func _on_cheat_command(cmd_name: String, args: Array[String]) -> void:
	match cmd_name:
		"win":
			_cmd_win(args)
		"lives":
			_cmd_lives(args)


# 本局题目来自哪个题库（埋点用）：实验组看 use_gc_bank，控制组按等级分 regular / lkstyle
func _get_dc_bank_source(current_lv: int, day_offset: int) -> String:
	if ABTestManager.dc_level.is_override_enabled():
		var sz: int = ABTestManager.dc_level.get_pool_size(current_lv, day_offset)
		if ABTestManager.dc_level.use_gc_bank(sz, day_offset):
			return "gc"
		return "regular"
	return "lkstyle" if current_lv > 200 else "regular"


# 公历日期 → 儒略日序号，用来算两个日期差几天
static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


# 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME


# 拼埋点用的结算参数（耗时、道具用量、错标数、复活次数等）
func _build_game_end_params(result: String) -> Dictionary:
	# 取通关耗时；拿不到就用墙上时钟兜底，避免上报 0
	var time_sec: int = _level_config.get("elapsed_sec", 0)
	if time_sec <= 0:
		time_sec = _get_elapsed_sec()
	if time_sec == 0:
		@warning_ignore("integer_division")
		var fallback_sec: int = (Time.get_ticks_msec() - _stat_start_ms) / 1000
		time_sec = fallback_sec

	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "time_total", time_sec)
	var sz: int = _level_config.get("size", 0)
	var cat_n: int = _board_view.count_cat_cells()
	# 几十个统计字段：本局 / 每日累计 / 道具 / 草稿 / 复活等，key 名即埋点字段名
	var params: Dictionary = {
		"qid": _build_qid(),
		"qrotate": Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
		"result": result,
		"game_type": Tracker.GameType.DAILY,
		"diffi": _get_diffi(),
		"level": GameState.get_current_level(),
		"strategy_layer": _level_config.get("rank", 0),
		"scale": sz,
		"hint": GameState.get_tool_count("hint"),
		"locate": GameState.get_tool_count("locate"),
		"hint_used": Tracker.get_stat("hint_used"),
		"locate_used": Tracker.get_stat("locate_used"),
		"hint_used_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "hint_used_total"),
		"locate_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "locate_used_total"),
		"hint_apply_used": Tracker.get_stat("hint_apply_used"),
		"hint_stop_used": Tracker.get_stat("hint_stop_used"),
		"hint_detail_used": Tracker.get_stat("hint_detail_used"),
		"clear_used": Tracker.get_stat("clear_used"),
		"clear_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "clear_used_total"),
		"draft_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_used_total"),
		"draft_time_total":
		int(GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_time_total_ms") / 1000.0),
		"draft_error_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_error_total"),
		"draft_correct_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_correct_total"),
		"coord_count": Tracker.get_stat("coord_count"),
		"step_used": Tracker.get_stat("step_used"),
		"step_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "step_total"),
		"gamedie_count": Tracker.get_stat("gamedie_count"),
		"restart_count": Tracker.get_stat("restart_count"),
		"time": time_sec,
		"time_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "time_total"),
		"percent": _level_config.get("beat_percent", 0.0),
		"cross_count": _board_view.count_mark_cells(),
		"invalid_sign": _board_view.count_error_cells(),
		"invalid_sign_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "invalid_sign_total"),
		"fail_sign": sz - cat_n,
		"erase_count": Tracker.get_stat("erase_count"),
		"revive_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "revive_count"),
		"rv_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "rv_count"),
		"hp_count": _lives,
	}
	return params
