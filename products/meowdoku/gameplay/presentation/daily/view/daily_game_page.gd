## 每日挑战游戏页：按日期选择题目，管理独立计时、残局恢复、重玩与挑战结算。
class_name DailyGamePage
extends BaseGamePage

const SettingScene: PackedScene = preload("res://products/meowdoku/app/features/setting/ui/setting_page.tscn") # 设置页场景预加载（本脚本内没引用，疑似历史遗留）

const _ELO_EXTRA_PLACEHOLDER: Dictionary = {
	"eloRating": -1.0,
	"eValue": -1.0,
	"kValue": -1.0,
	"playerRating": -1.0,
}
const _ELO_END_EXTRA_PLACEHOLDER: Dictionary = {
	"eloRating": -1.0,
	"eValue": -1.0,
	"kValue": -1.0,
	"playerRating": -1.0,
	"sValue": -1.0,
	"playerRatingNew": -1.0,
}

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _date_label: Label = $Root/VBoxContainer/Header/DateLabel # 头部日期文案（部分实验档会隐藏）
@onready var _level_display_value: Label = $Root/VBoxContainer/Header/LevelDisplay/Value # 头部「月/日」数字显示
## 计时文字（@onready 与变量声明分两行写的那个）
@onready
var _timer_label: Label = $Root/VBoxContainer/CatHeartRow/TimeContainer/HBoxContainer/TimerCtrl/TimerLabel

# ---- 运行时状态 ----
var _start_unix: float = 0.0 # 计时起点（Unix 秒）；广告占用的时长之后会补掉
var _start_date: String = "" # 开局日期 yyyy-mm-dd，通关时写进存档
var _ad_show_unix: float = 0.0 # 广告开始播放的时刻，> 0 表示有一段广告时长待扣除

var _dc_restore_snapshot: Dictionary = {} # 本次入场选中的每日快照副本；空字典走新题准备

var _clock_base_sec: float = 0.0 # 恢复时已有的耗时（秒），重新锚定时扣回起点
var _terminal_elapsed_sec: int = -1 # 首次胜利尝试冻结的秒数；重试保存不把弹窗等待计入成绩，-1 表示未冻结

@onready var _back_setting_header: BackAndSettingHeader = $Root/VBoxContainer/Header

var _entry_btn_lock_seq: int = 0 # 入场按钮锁序号；旧 toast/动画解锁回调必须匹配当前序号

var _in_game_costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID

@onready var _dc_toast: DailyStartToast = $Root/DcStartToast

static var debug_day_override: int = -1 # 调试开关：强制把「今天」当成第 N 天，-1 = 关闭


# ================= 生命周期 =================
## 埋点用的游戏类型：每日挑战
func _game_type() -> String:
	return Tracker.GameType.DAILY


## 连接每日页面表现与广告计时观察者，创建归本节点所有的快照防抖 Timer；业务会话在 on_show 后段提交。
func _ready() -> void:
	super._ready()
	_life_bar.refresh(_lives)

	_hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
	_hint_overlay.layer = 10
	_build_strategy_overlay()
	_ensure_ad_time_observers()

	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)

	get_viewport().size_changed.connect(_refresh_short_screen_compaction)

	$Root/VBoxContainer.sort_children.connect(_center_cat_progress_vertically)
	$Root/VBoxContainer.sort_children.connect(_relayout_cat_heart_row_for_progress)

	_endgame_save_timer = Timer.new()
	_endgame_save_timer.one_shot = true
	_endgame_save_timer.wait_time = _ENDGAME_SAVE_DEBOUNCE_SEC
	_endgame_save_timer.timeout.connect(_flush_endgame_snapshot)
	add_child(_endgame_save_timer)


## 每日入场总流程：判定新局/重开/重玩或合法恢复，准备题面与棋盘，再提交独立 daily 会话，最后安排教程和广告。
## 框架 presentation 版本保护整个展示，business generation 保护本次对局；同步通知和 await 后都可能需要复核。
func on_show(params: Dictionary = {}) -> void:
	# 先绑定本轮框架展示，再调用会染色、恢复或触发存档通知的服务；不能用重入后的新版本冒充旧请求。
	var entry_presentation: int = get_presentation_revision()
	_stop_entry_animation()
	_dc_cancel_inter_wait()
	_dc_cancel_late_ad_watch()
	_disconnect_endgame_persist()
	_reset_game_barrages()

	Tracker.set_active_game_type(Tracker.GameType.DAILY)

	ABTestManager.dye_at_game_start()

	ABTestManager.dye_at_game_start_dc()

	params = params.duplicate()
	# 这里只选择并复制可恢复数据，不提前清旧快照；后面选题/建盘失败仍能保留恢复机会。
	_dc_restore_snapshot = _resolve_endgame_restore(params)
	_clock_base_sec = 0.0
	if not _dc_restore_snapshot.is_empty():
		params.merge(DailyEndgameSnapshot.restore_params(_dc_restore_snapshot), true)
		_clock_base_sec = float(int(_dc_restore_snapshot["elapsed_sec"]))
	if entry_presentation != get_presentation_revision():
		return
	super.on_show(params)
	if entry_presentation != get_presentation_revision():
		return
	_ensure_ad_time_observers()
	var generation: int = _business_generation
	_terminal_elapsed_sec = -1

	_cat_progress_rotate_override = int(params.get("restore_cat_progress_rotate", -1))

	_board_view.visible = false

	var dt_local: Dictionary = Time.get_date_dict_from_system()
	_start_date = _local_date_string()

	var _explicit_status: String = params.get("_tracker_status", "")
	if _explicit_status == Tracker.GameStatus.RESTART:
		_stat_status = Tracker.GameStatus.RESTART
	elif _explicit_status == Tracker.GameStatus.REPLAY:
		_stat_status = Tracker.GameStatus.REPLAY
	elif GameState.get_daily_started_date() == _start_date:
		_stat_status = Tracker.GameStatus.CONTINUE
	else:
		_stat_status = Tracker.GameStatus.NEW
	_stat_start_ms = Time.get_ticks_msec()

	_se_last_step = Tracker.get_stat("step_used")
	if not _dc_restore_snapshot.is_empty():
		_se_last_step = mini(int(_dc_restore_snapshot["se_last_step"]), _se_last_step)

	if OS.is_debug_build() and not OS.has_feature("rel") and not CheatBus.command_issued.is_connected(_on_cheat_command):
		CheatBus.command_issued.connect(_on_cheat_command)

	const TRANSFORM_COUNT: int = 8

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

	var current_lv: int = GameState.get_current_level()
	if _dc_restore_snapshot.is_empty():
		if not _prepare_daily_puzzle(current_lv, day_offset):
			_block_round_entry()
			return
	else:
		_apply_snapshot_puzzle()
	var sz: int = int(_level_config["size"])
	_level_config["date"] = _start_date
	_level_config["is_restore"] = not _dc_restore_snapshot.is_empty()

	var dt: Dictionary = Time.get_datetime_dict_from_system()

	var month_str: String = tr("MONTH_ABBR_%d" % clampi(int(dt["month"]), 1, 12))
	_date_label.text = "%s %d" % [month_str, dt["day"]]
	_level_display_value.text = "%02d/%02d" % [dt["month"], dt["day"]]

	_date_label.visible = false

	_lives = 3

	_mistake_count = 0

	if not _dc_restore_snapshot.is_empty():
		_lives = clampi(int(_dc_restore_snapshot["lives"]), 1, _life_cap)
		_mistake_count = int(_dc_restore_snapshot["mistake_count"])
	_is_complete = false
	_wrong_guess_pending = false
	_hint_data = {}
	_last_placed_count = -1

	_like_hand_state = {
		"in_game_sec": 0.0,
		"last_cat_sec": 0.0,
		"triggered_count": 0,
		"clock_paused": false,
		"has_seen_first_cat": false,
		"cat_place_times": {},
		"missed_cross_triggered_cats": {},
		"latest_cat_key": "",
		"manually_x_marked_cells": {},
		"hint_marked_x_cells": {},
	}

	_continue_play_sec = 0.0
	_continue_clock_started = false

	_ad_show_unix = 0.0
	_anchor_clock()
	UIManager.hide_ui(UiName.DAILY_FAIL)
	UIManager.hide_ui(UiName.DAILY_WIN)
	_hint_overlay.visible = false

	_life_bar.refresh(_lives)
	_sync_tools_from_state()

	await get_tree().process_frame
	if entry_presentation != get_presentation_revision() or not _is_current_entry(generation):
		return

	_relayout_board()

	_entry_anim_playing = true

	_lock_entry_buttons()

	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var board_intro := $Root as BoardContainerCell_01
	if _anim_player.is_playing():
		_anim_player.stop()
		if (
			board_intro != null
			and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
		):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)

	_dc_defer_inter = ABTestManager.inter_timing.should_delay_start_interstitial()
	_dc_entry_skipped = false
	if not _dc_defer_inter:
		_anim_player.play("Appear")
		SoundManager.play(SoundManager.Kind.BOARD_ENTER)

		if (
			board_intro != null
			and not board_intro.animation_finished.is_connected(_on_appear_animation_finished)
		):
			board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)

	refresh_companion_costume_override()
	_in_game_costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	if _companion_costume_override != 0:
		_in_game_costume_id = _companion_costume_override
	elif ABTestManager.dc_costume.has_costume():
		_in_game_costume_id = ProfileService.get_today_costume()

	_level_config["companion_costume_override"] = _companion_costume_override
	_board_view.set_cat_costume(_in_game_costume_id)

	var color_seed: int = _level_config.get("daily_transform", 0)
	var color_map: Array[int] = LevelGenerator.compute_color_map_with_seed(
		sz, _puzzle["regions"], color_seed
	)

	if board_intro != null:
		board_intro.set_auto_trigger(false)
	if not _board_view.setup(sz, _puzzle["regions"], color_map, [], true):
		if board_intro != null:
			board_intro.set_auto_trigger(true)
		_stop_entry_animation()
		_block_round_entry()
		_report_business_failure(OperationResult.failure("board_setup_failed"))
		return
	_board_view.set_solution(_puzzle_sol_1d())

	_apply_cat_found_grid_dim()

	_restore_board_from_snapshot()

	if board_intro != null:
		board_intro.set_auto_trigger(true)

	if board_intro != null:
		board_intro.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame
	if entry_presentation != get_presentation_revision() or not _is_current_entry(generation):
		return

	_freeze_gameplay_policy(params)
	# 日期、重玩/恢复标记先进入候选；正式 daily 开局成功前不推进 live 的每日状态。
	_entry_state.stage_daily_entry(_start_date, _stat_status == Tracker.GameStatus.REPLAY, not _dc_restore_snapshot.is_empty(), int(_gameplay_policy.get("auto_mark_variant", 0)))
	var daily_plan: Dictionary = LevelSelector.prepare_existing_entry(_entry_state, 0, _level_config)
	daily_plan["restart"] = _stat_status == Tracker.GameStatus.RESTART
	if _stat_status == Tracker.GameStatus.REPLAY:
		daily_plan["new_game_id"] = Tracker.create_game_id()
	# 提交中的通知可能已打开新展示；只有仍拥有本轮入口时才能停止动画，不能误停新页。
	if not _commit_prepared_round(params, daily_plan):
		if entry_presentation == get_presentation_revision() and _is_current_entry(generation):
			_stop_entry_animation()
		return
	_start_gameplay_timing(true)
	Tracker.accept_game_start(Tracker.GameType.DAILY)
	if entry_presentation != get_presentation_revision() or not _is_current_entry(generation):
		return
	if _endgame_persist_active():
		_connect_endgame_persist()
	if not _dc_defer_inter:
		if board_intro != null:
			_apply_grid_ui_entry_anim(board_intro)
			board_intro.play()

		_board_view.on_board_entry_started(_grid_intro_sync_total(board_intro))

		_board_view.visible = true

	_update_remaining(true)

	if _combo_feedback_view == null:
		_combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
	if _combo_feedback_view != null:
		_combo_feedback_view.reset(_score_model.score)
	_connect_combo_signal()

	_reset_idle_hint()

	_idle_hint_round_count = 0

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
			0,
			"0",
			0,
			0.0,
			_level_config.get("rating", 0.0),
			_ELO_EXTRA_PLACEHOLDER,
		)
	)

	# 教程属于开局后的展示流程；取消后先核对页面身份，不让旧协程接着弹广告。
	await _maybe_show_costume_tutorial()
	if entry_presentation != get_presentation_revision() or not _is_current_entry(generation):
		return

	var ad_pos: String = Tracker.AdPos.NORMAL_START
	if _stat_status == Tracker.GameStatus.RESTART:
		ad_pos = Tracker.AdPos.NORMAL_RESTART
	elif _stat_status == Tracker.GameStatus.CONTINUE:
		ad_pos = Tracker.AdPos.NORMAL_CONTINUE
	elif _stat_status == Tracker.GameStatus.REPLAY:
		ad_pos = Tracker.AdPos.DC_RESTART

	var inter_elig: Dictionary = await _eval_start_interstitial(params, ad_pos)
	if entry_presentation != get_presentation_revision() or not _is_current_entry(generation):
		return

	if _dc_defer_inter and not inter_elig.get("replace_with_subscription", false):
		_dc_run_deferred_interstitial(ad_pos, inter_elig)

		_show_banner_if_eligible("daily")
		return

	if _dc_defer_inter:
		_dc_defer_inter = false
		_dc_play_entry_animation_now()

	var slot_occupied: bool = false
	if inter_elig.get("replace_with_subscription", false):
		slot_occupied = _show_subscription_instead_of_interstitial(ad_pos, inter_elig)
		if not slot_occupied:
			inter_elig = elig_without_replace_flag(inter_elig)
	if not slot_occupied:
		slot_occupied = _try_show_start_interstitial(ad_pos, inter_elig)
	if slot_occupied:
		_mark_fullscreen_ad_slot_shown()

	_show_banner_if_eligible("daily")


## 停止每日入口动画并在基类撤销业务代次前保存最后快照，随后断开持久化与广告等待；重开不沿用旧计时回调。
func on_hide() -> void:
	_stop_entry_animation()
	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	# 先保存再断监听、撤销基类代次；keep_saved_session 避免退出清理改写原快照的会话归属。
	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_flush_endgame_snapshot(true)
		_disconnect_endgame_persist()
	super.on_hide()

	_ad_show_unix = 0.0
	if _dc_toast != null:
		_dc_toast.hide_toast()
	var board_intro := $Root as BoardContainerCell_01
	if (
		board_intro != null
		and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
	):
		board_intro.animation_finished.disconnect(_on_appear_animation_finished)

	_dc_cancel_inter_wait()
	_dc_cancel_late_ad_watch()


## 按当前 Unix 起点计算已用整秒，最小为 0；恢复时的已用时长已折入起点。
func _get_elapsed_sec() -> int:
	return maxi(0, int(Time.get_unix_time_from_system() - _start_unix))


## 用当前或指定 Unix 时间扣除已恢复秒数，建立计时起点并刷新显示。
func _anchor_clock(anchor_unix: float = 0.0) -> void:
	var base_unix: float = anchor_unix if anchor_unix > 0.0 else Time.get_unix_time_from_system()
	_start_unix = base_unix - _clock_base_sec
	if _clock_base_sec > 0.0:
		_apply_elapsed_to_label(int(_clock_base_sec))
	else:
		_timer_label.text = "00:00"


## 计时器心跳：只刷新文字
func _on_clock_timer_timeout() -> void:
	_refresh_timer_label()


## 按当前已用秒数刷新计时文字
func _refresh_timer_label() -> void:
	_apply_elapsed_to_label(_get_elapsed_sec())


## 把秒数写成 mm:ss；超过 1 小时改成 hh:mm:ss 并把字号调小
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


## 切后台先执行共享时钟收尾，再停防抖并尝试写入每日恢复快照。
func _on_application_focus_out() -> void:
	super._on_application_focus_out()

	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	_flush_endgame_snapshot()


const _ENDGAME_SAVE_DEBOUNCE_SEC: float = 0.5 # 普通标记变化的快照合并窗口（秒）

var _endgame_save_timer: Timer = null # 本节点拥有的一次性防抖 Timer，离页停止、节点释放时随之释放


## 判断当前每日局是否应保留镜像快照：需已就绪、仍为当天、开启功能、非调试/重玩且当天尚未完成。
func _endgame_persist_active() -> bool:
	if not _entry_ready or _start_date != _local_date_string():
		return false
	if not ABTestManager.dc_endgame_save.is_enabled():
		return false
	if DailyGamePage.debug_day_override >= 0:
		return false
	if _stat_status == Tracker.GameStatus.REPLAY:
		return false
	return GameState.get_daily_completed_date() != _start_date


## 接入每日格子变更保存监听；重复调用不增加第二条连接。
func _connect_endgame_persist() -> void:
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_board_view.cell_state_changed.connect(_persist_endgame_snapshot)


## 停止延迟保存并断开格子监听；结算后不再让旧格子动画重写每日快照。
func _disconnect_endgame_persist() -> void:
	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	if (
		_board_view != null
		and _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot)
	):
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)


## 忽略恢复来源的格子通知；猫/错误格排本代次的延迟保存，其余变更合并到防抖计时器。
func _persist_endgame_snapshot(_row: int, _col: int, state: int, source: int) -> void:
	if source == BoardView.ChangeSource.RESTORE:
		return
	if state == CellState.CAT or state == CellState.ERROR:
		_endgame_save_timer.stop()
		_flush_endgame_for_generation.call_deferred(_business_generation)
	else:
		_endgame_save_timer.start()


## 构造并提交每日镜像快照；没有进度时提交清除，写失败显示错误，不假装本次已保存。
## 离页可沿用原 session_id；兼容镜像保存与胜负结算分开，终局不会通过这条链重复结算。
func _flush_endgame_snapshot(keep_saved_session: bool = false) -> void:
	if _is_complete or not _endgame_persist_active():
		return
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	var override: Dictionary = {}
	if keep_saved_session:
		var saved_session: String = str(
			GameState.get_daily_endgame_snapshot().get("session_id", "")
		)
		if not saved_session.is_empty():
			override["session_id"] = saved_session
	var snapshot: Dictionary = _build_endgame_snapshot(override)
	# 没有玩家进度只请求清镜像；不先清再写，写失败由 GameState 保留原聚合状态。
	if not DailyEndgameSnapshot.has_progress(snapshot):
		if not GameState.clear_daily_endgame_snapshot():
			_report_business_failure(OperationResult.failure("daily_snapshot_save_failed"))
		return
	if not GameState.set_daily_endgame_snapshot(snapshot):
		_report_business_failure(OperationResult.failure("daily_snapshot_save_failed"))


## 停止每日防抖后请求清除镜像快照；这个包装不返回存储结果，正式胜利清理由结算事务完成。
func _clear_endgame_snapshot() -> void:
	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	GameState.clear_daily_endgame_snapshot()


## 把棋盘分解为猫、标记和错误坐标，允许临时覆盖待表现格值；不直接修改棋盘。
func _collect_board_cells(override_cells: Dictionary = {}) -> Dictionary:
	var board: Array = _board_view.get_board()
	var cells: Dictionary = _snapshot_cell_overrides(override_cells)
	var placed_cats: Array = []
	var marks: Array = []
	var errors: Array = []
	for row in range(board.size()):
		var board_row: Array = board[row]
		for col in range(board_row.size()):
			var state: int = int(board_row[col])
			var cell_key: Vector2i = Vector2i(row, col)
			if cells.has(cell_key):
				state = int(cells[cell_key])
			if state == CellState.CAT:
				placed_cats.append([row, col])
			elif state == CellState.MARK:
				marks.append([row, col])
			elif state == CellState.ERROR:
				errors.append([row, col])
	return {"placed_cats": placed_cats, "marks": marks, "errors": errors}


## 构造每日恢复数据，并附上业务 round/attempt、历史及冻结内容策略；只组装字典，不在这里落盘。
func _build_endgame_snapshot(override: Dictionary = {}) -> Dictionary:
	var override_cells: Dictionary = override.get("cells", {})
	var score_state: Dictionary = {
		"score": _score_model.score,
		"combo": int(override.get("combo", _score_model.combo)),
		"max_combo": _score_model.max_combo,
		"se_count": int(override.get("se_count", _se_count)),
		"se_last_step": _se_last_step,
	}
	var toast_state: Dictionary = {
		"operable_sec": _operable_sec,
		"cat_toast": _cat_toast_tracker.export_state(),
		"cat_progress_rotate_start": _cat_progress_rotate_start,
	}
	var snapshot: Dictionary = DailyEndgameSnapshot.build(
		_start_date,
		str(override.get("session_id", SessionManager.session_id)),
		_level_config,
		_puzzle["regions"],
		_puzzle_sol_1d(),
		_collect_board_cells(override_cells),
		int(override.get("lives", _lives)),
		_mistake_count,
		score_state,
		_get_elapsed_sec(),
		toast_state
	)
	# 应用会话 session_id 用于每日恢复策略；business_round_id 则标识持久对局，两者不能混用。
	snapshot["business_round_id"] = _business_session.round_id() if _business_session != null else _business_restored_id
	snapshot["business_attempt_sequence"] = _business_attempt_sequence
	snapshot["step_history"] = _business_history.duplicate(true)
	snapshot["highlight_cursor"] = _business_highlight_cursor
	snapshot["gameplay_policy_snapshot"] = _gameplay_policy_snapshot()
	snapshot["content_release"] = _round_content_release
	snapshot["content_provenance"] = _round_content_provenance.duplicate(true)
	snapshot["policy_snapshot"] = _round_policy.duplicate(true)
	return snapshot


func _local_date_string() -> String:
	var date_dict: Dictionary = Time.get_date_dict_from_system()
	return (
		"%d-%02d-%02d"
		% [date_dict.get("year", 2026), date_dict.get("month", 1), date_dict.get("day", 1)]
	)


## 把日期、会话策略、重开/重玩意图与生命上限交给快照校验；可恢复则返回副本，否则返回空字典且不先清旧档。
func _resolve_endgame_restore(params: Dictionary) -> Dictionary:
	if DailyGamePage.debug_day_override >= 0:
		return {}
	var today: String = _local_date_string()
	var explicit_status: String = params.get("_tracker_status", "")
	var forced_fresh: bool = (
		explicit_status == Tracker.GameStatus.RESTART
		or explicit_status == Tracker.GameStatus.REPLAY
	)
	var snapshot: Dictionary = GameState.get_daily_endgame_snapshot()
	var restorable: bool = DailyEndgameSnapshot.should_restore(
		snapshot,
		ABTestManager.dc_endgame_save.is_enabled(),
		ABTestManager.dc_endgame_save.requires_same_session(),
		forced_fresh,
		GameState.get_daily_started_date() == today,
		today,
		SessionManager.session_id,
		_life_cap
	)
	if restorable:
		return snapshot.duplicate(true)
	return {}


## 从已校验快照恢复题面和配置并规范整数类型，不重新从当天题库选择，避免恢复成另一题。
func _apply_snapshot_puzzle() -> void:
	var saved_config: Dictionary = _dc_restore_snapshot["level_config"]
	_level_config = saved_config.duplicate(true)
	for int_key: String in [
		"size", "rank", "daily_index", "daily_transform", "bank_idx", "bank_transform"
	]:
		if _level_config.has(int_key):
			_level_config[int_key] = int(_level_config[int_key])
	_level_config["is_daily"] = true
	_level_config["prefill_count"] = 0
	_level_config["prefill_positions"] = []
	var saved_regions: Array = _dc_restore_snapshot["regions"]
	var int_regions: Array = []
	for region_row: Array in saved_regions:
		var int_row: Array = []
		for region_id: Variant in region_row:
			int_row.append(int(region_id))
		int_regions.append(int_row)
	var saved_solution: Array = _dc_restore_snapshot["solution"]
	var solution_1d: Array = []
	for column: Variant in saved_solution:
		solution_1d.append(int(column))
	_puzzle = {
		"regions": int_regions,
		"solution":
		DailyEndgameSnapshot.solution_grid(solution_1d, int(_dc_restore_snapshot["size"])),
	}


## 以 RESTORE 来源填回猫、标记和错误格并初始化演出触发记录；这些恢复通知不视为玩家新操作。
func _restore_board_from_snapshot() -> void:
	if _dc_restore_snapshot.is_empty():
		return
	var placed_cats: Array = _dc_restore_snapshot["placed_cats"]
	for pos: Array in placed_cats:
		_board_view.set_cell_state(
			int(pos[0]), int(pos[1]), CellState.CAT, false, true, BoardView.ChangeSource.RESTORE
		)
	var marks: Array = _dc_restore_snapshot["marks"]
	for pos: Array in marks:
		_board_view.set_cell_state(
			int(pos[0]), int(pos[1]), CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
	var errors: Array = _dc_restore_snapshot["errors"]
	for pos: Array in errors:
		var row: int = int(pos[0])
		var col: int = int(pos[1])
		_board_view.set_cell_state(
			row, col, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
		_board_view.mark_cell_error(row, col, BoardView.ChangeSource.RESTORE)

	_seed_full_mark_fired_units_from_board("每日残局复原")


## 将尚在错猜动画中的格子按 ERROR 保存，同时带上已扣生命和清零连击；保存失败保留错误提示。
func _save_endgame_for_pending_wrong_guess(row: int, col: int) -> void:
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	var override: Dictionary = {
		"cells": {Vector2i(row, col): CellState.ERROR},
		"lives": _lives,
		"combo": 0,
		"se_count": 0,
	}

	_endgame_save_timer.stop()
	if not GameState.set_daily_endgame_snapshot(_build_endgame_snapshot(override)):
		_report_business_failure(OperationResult.failure("daily_snapshot_save_failed"))


func _on_application_focus_in() -> void:
	super._on_application_focus_in()
	_compensate_ad_time()
	_refresh_timer_label()

	if not _dc_inter_wait.is_empty():
		_dc_inter_wait["done"] = true
	elif _dc_late_lock_active:
		_dc_release_late_lock("focus_in")


## Base hide clears request callbacks; a reused daily page must reinstall its timing observers.
func _ensure_ad_time_observers() -> void:
	if not UniKitManager.ad_closed.is_connected(_on_ad_closed):
		UniKitManager.ad_closed.connect(_on_ad_closed)
	if not UniKitManager.ad_shown.is_connected(_on_ad_shown_for_timer):
		UniKitManager.ad_shown.connect(_on_ad_shown_for_timer)


func _on_ad_shown_for_timer(placement_id: String) -> void:
	if not is_showing():
		return
	if placement_id == AdPlacement.REWARD:
		_ad_show_unix = Time.get_unix_time_from_system()


func _mark_fullscreen_ad_slot_shown() -> void:
	_ad_show_unix = Time.get_unix_time_from_system()
	_anchor_clock(_ad_show_unix)


func _on_interstitial_subscription_closed(
	ad_position: String, elig: Dictionary, should_play_interstitial: bool
) -> bool:
	var shown: bool = super._on_interstitial_subscription_closed(
		ad_position, elig, should_play_interstitial
	)
	if not shown:
		_compensate_ad_time()
		_refresh_timer_label()
	return shown


func _compensate_ad_time() -> void:
	if _ad_show_unix <= 0.0:
		return
	var now_unix: float = Time.get_unix_time_from_system()
	var ad_duration: float = now_unix - _ad_show_unix
	print("[DailyGame] ad compensated %.1fs" % ad_duration)
	_start_unix = minf(_start_unix + ad_duration, now_unix)
	_ad_show_unix = 0.0


func _on_ad_closed(_placement_id: String) -> void:
	if not is_showing():
		return
	_compensate_ad_time()
	_refresh_timer_label()


func _on_gear_btn_pressed() -> void:
	if _is_complete:
		return
	_reset_game_barrages()
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	_clock_timer.stop()

	_exit_draft_mode_and_clear()
	_clear_draft_rollback_state()
	UIManager.hide_all_except([UiName.HOME])
	UIManager.show_ui(UiName.HOME)


func _on_appear_animation_finished() -> void:
	if not _is_round_entry_ready() or not _is_current_entry(_business_generation):
		return
	super._on_appear_animation_finished()

	if not _dc_entry_skipped:
		VibrateManager.play_at(VibrateManager.Pos.BOARD_INTRO)

	var lock_seq: int = _entry_btn_lock_seq

	if _try_show_dc_start_toast():
		_unlock_entry_buttons_after_toast(lock_seq)
	else:
		_unlock_entry_buttons()


func _try_show_dc_start_toast() -> bool:
	if not ABTestManager.dc_start_toast.is_enabled():
		return false
	if not _dc_restore_snapshot.is_empty():
		return false

	if GameState.get_current_level() < 11:
		return false
	var is_first: bool = _stat_status == Tracker.GameStatus.NEW
	var pick: Dictionary = DcStartToastTextPool.resolve(is_first)
	(
		_dc_toast
		. show_toast(
			{
				"text_key": pick.text_key,
				"pct_str": pick.pct_str,
			}
		)
	)
	return true


func _wait_dc_toast_hidden_if_any() -> void:
	if _dc_toast == null or not _dc_toast.visible:
		return
	while _dc_toast.visible:
		await _dc_toast.visibility_changed


var _dc_defer_inter: bool = false

var _dc_entry_skipped: bool = false

const _DC_INTER_DELAY_AFTER_BOARD_SEC: float = 0.4

const _DC_SHOW_CONFIRM_SEC: float = 2.0

const _DC_LATE_LOCK_SEC: float = 3.0

var _dc_inter_wait: Dictionary = {}

var _dc_ad_cbs: Array = []
var _dc_show_confirm_timer: Timer = null

var _dc_late_lock_active: bool = false
var _dc_late_cbs: Array = []
var _dc_late_lock_timer: Timer = null


func _dc_run_deferred_interstitial(ad_pos: String, elig: Dictionary) -> void:
	var generation: int = _business_generation
	if not elig.get("eligible", false):
		_dc_play_entry_animation_now()
		return
	_dc_place_board_without_intro()

	_anim_player.play("Appear")

	await get_tree().create_timer(_DC_INTER_DELAY_AFTER_BOARD_SEC).timeout
	if not _is_current_entry(generation):
		return
	if not is_showing():
		return

	if not _try_show_start_interstitial(ad_pos, elig):
		_dc_finish_entry_after_interstitial()
		return
	_mark_fullscreen_ad_slot_shown()
	await _dc_await_interstitial_closed()
	if not _is_current_entry(generation):
		return
	if not is_showing():
		return
	_dc_finish_entry_after_interstitial()


func _dc_place_board_without_intro() -> void:
	_dc_entry_skipped = true
	_board_view.visible = true
	_board_view.on_board_entry_started(0.0)
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		board_intro.set_auto_trigger(false)
		if board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)
		_dc_reveal_board_container(board_intro)


func _dc_reveal_board_container(board_intro: BoardContainerCell_01) -> void:
	if not (board_intro.board_view is CanvasItem):
		return
	var board_container: CanvasItem = board_intro.board_view as CanvasItem
	var col: Color = board_container.modulate
	col.a = 1.0
	board_container.modulate = col


func _dc_play_entry_animation_now() -> void:
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		_apply_grid_ui_entry_anim(board_intro)
		board_intro.play()
		if not board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)
	_board_view.on_board_entry_started(_grid_intro_sync_total(board_intro))
	_board_view.visible = true
	_anim_player.play("Appear")
	SoundManager.play(SoundManager.Kind.BOARD_ENTER)


func _dc_await_interstitial_closed() -> void:
	var generation: int = _business_generation
	var state := {"done": false}
	_dc_inter_wait = state
	var on_closed: Callable = func(pid: String) -> void:
		if pid == AdPlacement.INTERSTITIAL:
			state.done = true
	var on_error: Callable = func(pid: String, _msg: String) -> void:
		if pid == AdPlacement.INTERSTITIAL:
			state.done = true
	UniKitManager.ad_closed.connect(on_closed)
	UniKitManager.ad_error_occurred.connect(on_error)
	_dc_ad_cbs = [on_closed, on_error]
	_dc_arm_show_confirm(state)

	while not state.done and _is_current_entry(generation):
		await get_tree().process_frame
	if is_same(_dc_inter_wait, state):
		_dc_cancel_inter_wait()


func _dc_arm_show_confirm(state: Dictionary) -> void:
	if not UniKitManager.is_ad_impression_signal_available():
		return
	var on_impression: Callable = func(data: Dictionary) -> void:
		if String(data.get("placement_id", "")) != AdPlacement.INTERSTITIAL:
			return

		_dc_disarm_show_confirm()
	UniKitManager.ad_impression_received.connect(on_impression)
	_dc_ad_cbs.append(on_impression)
	_dc_show_confirm_timer = create_countdown(
		_DC_SHOW_CONFIRM_SEC,
		func() -> void:
			_dc_show_confirm_timer = null
			if state.get("done", false):
				return
			print(
				"[DC-Inter] %.1fs 内未收到 ad impression → 判定插屏未上屏,主动恢复进关(防卡死)" % _DC_SHOW_CONFIRM_SEC
			)
			state.done = true

			_dc_arm_late_ad_watch()
	)


func _dc_disarm_show_confirm() -> void:
	if _dc_show_confirm_timer != null:
		remove_timer(_dc_show_confirm_timer)
		_dc_show_confirm_timer = null


func _dc_cancel_inter_wait() -> void:
	if not _dc_inter_wait.is_empty():
		_dc_inter_wait["done"] = true
		_dc_inter_wait = {}
	for cb in _dc_ad_cbs:
		if UniKitManager.ad_closed.is_connected(cb):
			UniKitManager.ad_closed.disconnect(cb)
		if UniKitManager.ad_error_occurred.is_connected(cb):
			UniKitManager.ad_error_occurred.disconnect(cb)
		if UniKitManager.ad_impression_received.is_connected(cb):
			UniKitManager.ad_impression_received.disconnect(cb)
	_dc_ad_cbs = []
	_dc_disarm_show_confirm()


func _dc_arm_late_ad_watch() -> void:
	if not UniKitManager.is_ad_impression_signal_available():
		return
	_dc_cancel_late_ad_watch()
	var on_late: Callable = func(data: Dictionary) -> void:
		if String(data.get("placement_id", "")) != AdPlacement.INTERSTITIAL:
			return
		_dc_on_late_ad_impression()
	UniKitManager.ad_impression_received.connect(on_late)
	_dc_late_cbs = [on_late]


func _dc_on_late_ad_impression() -> void:
	if _dc_late_lock_active:
		return
	_dc_late_lock_active = true
	print("[DC-Inter] 迟到的 ad impression 到达(超时判定后广告仍上屏)→ 重新锁交互")
	_dc_set_late_locked(true)
	var on_closed: Callable = func(pid: String) -> void:
		if pid == AdPlacement.INTERSTITIAL:
			_dc_release_late_lock("ad_closed")
	UniKitManager.ad_closed.connect(on_closed)
	_dc_late_cbs.append(on_closed)
	_dc_late_lock_timer = create_countdown(
		_DC_LATE_LOCK_SEC,
		func() -> void:
			_dc_late_lock_timer = null
			_dc_release_late_lock("timeout")
	)


func _dc_release_late_lock(source: String) -> void:
	if not _dc_late_lock_active:
		return
	_dc_late_lock_active = false
	print("[DC-Inter] 迟到锁解除(source=%s)" % source)
	_dc_set_late_locked(false)
	_dc_cancel_late_ad_watch()


func _dc_cancel_late_ad_watch() -> void:
	if _dc_late_lock_active:
		_dc_late_lock_active = false
		_dc_set_late_locked(false)
	for cb in _dc_late_cbs:
		if UniKitManager.ad_impression_received.is_connected(cb):
			UniKitManager.ad_impression_received.disconnect(cb)
		if UniKitManager.ad_closed.is_connected(cb):
			UniKitManager.ad_closed.disconnect(cb)
	_dc_late_cbs = []
	if _dc_late_lock_timer != null:
		remove_timer(_dc_late_lock_timer)
		_dc_late_lock_timer = null


func _dc_set_late_locked(locked: bool) -> void:
	if _entry_anim_playing:
		return
	if _board_view != null:
		_board_view.set_touch_enabled(not locked)
	if locked:
		_lock_entry_buttons()
	else:
		_unlock_entry_buttons()


func _dc_finish_entry_after_interstitial() -> void:
	_on_appear_animation_finished()


func _unlock_entry_buttons_after_toast(seq: int) -> void:
	var generation: int = _business_generation
	await _wait_dc_toast_hidden_if_any()
	if not _is_current_entry(generation):
		return
	if seq != _entry_btn_lock_seq:
		return
	_unlock_entry_buttons()


func _lock_entry_buttons() -> void:
	_entry_btn_lock_seq += 1
	_back_setting_header.lock_buttons()


func _unlock_entry_buttons() -> void:
	_back_setting_header.unlock_buttons()


## 把每日重开交给共享转场令牌，防止双击或同步回调重复结算。
func _on_restart_requested() -> void:
	await _run_round_transition(_restart_daily_round)


func _on_rule_violated(rule: int, additive: bool = false) -> void:
	_play_rule_highlight(rule, additive)


func _reward_pos_for(kind: String) -> String:
	if kind == ToolKind.LOCATE:
		return Tracker.AdPos.PROPS_DAILY_LOCATE
	if kind == ToolKind.MOUSE:
		return Tracker.AdPos.PROPS_DAILY_MOUSE
	if kind == ToolKind.DRAFT:
		return Tracker.AdPos.PROPS_DAILY_DRAFT
	return Tracker.AdPos.PROPS_DAILY_HINT


## 每日失败入口；已终局或正在等待保存重试时忽略，通过共享转场令牌串行结算。
func _on_game_fail() -> void:
	if _is_complete or _settlement_pending:
		return
	await _run_round_transition(_finish_daily_fail)


## 按每日日期与同次尝试幂等键提交失败，成功后才停保存、计时并打开每日失败页。
func _finish_daily_fail(context: Dictionary) -> void:
	var settlement_id: String = _business_settlement_id()
	if not _is_current_round_transition(context):
		return
	var end_params: Dictionary = _build_game_end_params(Tracker.GameResult.FAIL)
	var settled: Dictionary = GameState.settle_daily_round(settlement_id, _start_date, "fail", 0, 0.0, _business_runtime(), _daily_settlement_context())
	_publish_round_end(settled, end_params)
	if not _is_current_round_transition(context):
		return
	if not settled.get("ok", false):
		_retry_round_transition(context, settled, _on_game_fail)
		return
	_is_complete = true
	_disconnect_endgame_persist()
	_reset_game_barrage_session_state()

	_exit_draft_mode_and_clear()
	_clock_timer.stop()

	pause_like_hand_clock()
	_stop_idle_tool_hint()
	_destroy_banner()

	ABTestManager.dye_at_game_fail_end()

	VibrateManager.play_at(VibrateManager.Pos.DAILY_FAIL)
	var sz: int = _level_config.get("size", 12)
	var placed: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				placed += 1
	var remaining_cats: int = sz - placed
	var fail := (
		UIManager
		. show_ui(
			UiName.DAILY_FAIL,
			{
				"level_config": _level_config,
				"remaining_cats": remaining_cats,
				"cat_progress": build_cat_progress_snapshot(),
				"gameplay_policy_snapshot": _gameplay_policy_snapshot(),
				"gameplay_level": GameState.get_current_level(),
			}
		)
	)
	if not _is_current_round_transition(context):
		return
	if fail != null and not fail.revive_requested.is_connected(_on_revive_requested):
		fail.revive_requested.connect(_on_revive_requested)
	if fail != null and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
		fail.revive_ad_started.connect(_on_revive_ad_started)


## 广告开始播：先把棋盘上的猫全部退回待机，广告结束后再复原
func _on_revive_ad_started() -> void:
	_board_view.revive_all_cat_to_idle()


## 在盘面副本中撤回草稿致命格，再交给共享复活事务；生命与尝试号成功提交后才恢复页面。
func _on_revive_requested(revive_context: Dictionary = {}) -> void:
	var board: Array = _board_view.get_board().duplicate(true)
	for pos: Vector2i in _draft_lethal_wrong_cells:
		board[pos.x][pos.y] = CellState.EMPTY
	_request_revive(revive_context, {"board": board}, _present_daily_revive)


## 复活提交成功后恢复每日交互与计时，再接回保存监听并排一笔本代次快照。
func _present_daily_revive() -> void:
	var generation: int = _business_generation
	# 隐藏失败弹窗也能同步触发外部逻辑；返回后重新验代次和就绪状态再恢复交互。
	UIManager.hide_ui(UiName.DAILY_FAIL)
	if not _is_current_entry(generation) or not _is_round_entry_ready() or _is_complete:
		return

	_board_view.set_touch_enabled(true)

	_block_near_death_for_current_level()

	_life_bar.refresh(_lives)

	_life_bar.revive_all()
	_clock_timer.start()

	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

	resume_like_hand_clock()

	_board_view.revive_all_cat_to_idle()

	_rollback_draft_lethal_cells()

	_show_banner_if_eligible("daily")
	_restart_game_barrages_after_continue()

	_connect_endgame_persist()
	_flush_endgame_for_generation.call_deferred(generation)


func _is_no_mistake_level() -> bool:
	return _mistake_count == 0


## 每日胜利入口；尚未结算的同一次尝试由共享令牌独占，避免完成信号重入。
func _on_game_win() -> void:
	if _is_complete or _settlement_pending:
		return
	await _run_round_transition(_finish_daily_win)


## 先冻结终局用时并原子提交每日结果、统计、服装资格和最终盘面；成功回执决定后续展示，保存失败保留重试。
func _finish_daily_win(context: Dictionary) -> void:
	# 第一次胜利请求固定成绩用时，后续保存重试不把等待确认的时间算进挑战成绩。
	if _terminal_elapsed_sec < 0:
		_terminal_elapsed_sec = _get_elapsed_sec()
	var settlement_id: String = _business_settlement_id()
	if not _is_current_round_transition(context):
		return
	var elapsed_sec: int = _terminal_elapsed_sec
	_level_config["elapsed_sec"] = elapsed_sec
	var raw_percent: float = float(_level_config.get("beat_percent", -1.0))
	if raw_percent < 0.0:
		raw_percent = DailyStats.beat_percent(elapsed_sec, int(_level_config.get("rank", 4)), int(_level_config.get("size", 12)), ABTestManager.dc_beat_percent.is_anchor_curve())
		_level_config["beat_percent"] = raw_percent
	var end_params: Dictionary = _build_game_end_params(Tracker.GameResult.WIN)
	# 每日完成、今日统计、签到/服装资格与快照清理由统一候选结算处理，UI 只接收其展示数据。
	var settled: Dictionary = GameState.settle_daily_round(settlement_id, _start_date, "win", elapsed_sec, raw_percent, _win_business_runtime(), _daily_settlement_context())
	_publish_round_end(settled, end_params)
	if not _is_current_round_transition(context):
		return
	if not settled.get("ok", false):
		_retry_round_transition(context, settled, _on_game_win)
		return
	_accept_win_bonus(settled)
	var presentation: Dictionary = settled.get("presentation", {})
	for key: String in ["today_cat_before", "today_cat_after", "today_mark_before", "today_mark_after"]:
		if presentation.has(key):
			_level_config[key] = presentation[key]
	_is_complete = true
	_disconnect_endgame_persist()
	PowerSaver.wake(_WIN_REPLAY_FULL_FPS_SEC)
	_reset_game_barrage_session_state()
	_exit_draft_mode_and_clear()
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()
	_apply_elapsed_to_label(elapsed_sec)
	pause_like_hand_clock()
	if not await _await_mouse_completion_anim_if_needed():
		return
	if not _is_current_round_transition(context):
		return
	SoundManager.stop(SoundManager.Kind.MARK_CAT)

	_board_view.replay_all_cat_appear(ABTestManager.found_cat_animation.win_replay_anim_name())
	VibrateManager.play_at(VibrateManager.Pos.DAILY_WIN)
	_cleanup_hint()
	await get_tree().process_frame
	if not _is_current_round_transition(context):
		return

	# 服装是否解锁来自成功回执；这里不再调用 ProfileService 旁路发放一次。
	var costume_unlocked: bool = bool(presentation.get("costume_unlocked", false))

	_level_config["costume_unlock_pending"] = costume_unlocked
	_level_config["costume_id"] = _in_game_costume_id

	await _play_auto_cross_bonus_sequence()
	if not _is_current_round_transition(context):
		return


	var toast_was_shown: bool = await _play_win_toast_and_wait()
	if not _is_current_round_transition(context):
		return
	_level_config["toast_was_shown"] = toast_was_shown

	var streak_consumed_appear_delay: bool = false
	if not ABTestManager.daily_streak.is_settle_reorder():
		streak_consumed_appear_delay = await _try_run_streak_flow_after_win(
			&"challenge", toast_was_shown
		)
		if not _is_current_round_transition(context):
			return

	var costume_page_shown: bool = await _run_costume_unlock_flow()
	if not _is_current_round_transition(context):
		return

	_level_config["skip_appear_delay"] = streak_consumed_appear_delay or costume_page_shown

	_level_config["final_score"] = _score_model.score
	_level_config["max_combo"] = _score_model.max_combo
	var win_page := UIManager.show_ui(
		_win_ui_name(), {"level_config": _level_config, "board_view": _board_view}
	)

	if win_page != null and not win_page.replay_requested.is_connected(_on_win_replay_requested):
		win_page.replay_requested.connect(_on_win_replay_requested)


## 本页对应的通关页 UI 名（每日挑战固定）
func _win_ui_name() -> StringName:
	return UiName.DAILY_WIN


const _TUTORIAL_CLOSE_TIMEOUT_SEC: float = 60.0 # 教程等待上限（秒）；超时放行入场但不记已完成


func in_game_costume_id() -> int:
	return _in_game_costume_id


## 展示结算已授予的服装，不在弹窗动画中发奖；无待展示或父局失效返回 false。
## 子窗口关闭、销毁或换展示版本都结束等待，返回 true 只表示父局仍在并已尝试展示。
func _run_costume_unlock_flow() -> bool:
	var generation: int = _business_generation
	if not bool(_level_config.get("costume_unlock_pending", false)):
		return false
	_level_config["costume_unlock_pending"] = false
	var page := (
		UIManager
		. show_ui(
			UiName.DC_COSTUME_UNLOCK,
			{
				"beat_percent": float(_level_config.get("beat_percent", 50.0)),
				"costume_id":
				int(_level_config.get("costume_id", CostumeCatalog.DEFAULT_COSTUME_ID)),
			}
		)
	)
	if page == null:
		push_error("DailyGamePage: dc_costume unlock page 打不开,外观已发但玩家看不到解锁画面")
		return false
	var revision: int = page.get_presentation_revision()
	while is_instance_valid(page) and page.is_showing() and page.get_presentation_revision() == revision and _is_current_entry(generation):
		await get_tree().process_frame
	if not _is_current_entry(generation):
		return false
	return true


## 暂停每日时钟并等待本次教程正常关闭；父页取消、子页销毁/刷新或超时均不能记为教程完成。
## 等待由本页 presentation 管理，子页通过 WeakRef 查询；正常完成且身份仍匹配才持久标记已看。
func _maybe_show_costume_tutorial() -> void:
	var generation: int = _business_generation
	var presentation_revision: int = get_presentation_revision()
	if not ABTestManager.dc_costume.has_costume():
		return
	if ProfileService.is_costume_tutorial_shown():
		return

	await get_tree().process_frame
	if not _is_current_entry(generation):
		return
	var page := (
		UIManager
		. show_ui(
			UiName.DC_COSTUME_TUTORIAL,
			{
				"costume_id": _in_game_costume_id,
				"spotlight": _life_capsule_for_tutorial(),
			}
		)
	)
	if page == null:
		push_error("DailyGamePage: dc_costume tutorial page 打不开,跳过教学")
		return

	_hold_clock_for_tutorial()

	var state: Dictionary = {"closed": false}
	var on_closed: Callable = func() -> void: state["closed"] = true
	var tutorial_page := page as DcCostumeTutorialPage
	if tutorial_page == null:
		push_error("DailyGamePage: DC_COSTUME_TUTORIAL 指向的不是 DcCostumeTutorialPage,跳过教学")
		_start_clock_after_tutorial()
		return
	var tutorial_revision: int = tutorial_page.get_presentation_revision()
	# 闭包只捕获 WeakRef，避免子页先释放时仍捕获失效 Node；每帧再取当前实例。
	var tutorial_ref: WeakRef = weakref(tutorial_page)
	tutorial_page.tutorial_closed.connect(on_closed, CONNECT_ONE_SHOT)

	var clock: Tween = create_tween()
	clock.tween_interval(_TUTORIAL_CLOSE_TIMEOUT_SEC + 1.0)
	# predicate 为 true 表示这次等待可结束，可能是正常关闭也可能是取消/超时，不能直接当成教程完成。
	var wait_completed: bool = await wait_presentation_until(func() -> bool:
		var current_tutorial: UIFrameWindow = tutorial_ref.get_ref() as UIFrameWindow
		return state["closed"] or not is_instance_valid(current_tutorial) \
			or current_tutorial.get_presentation_revision() != tutorial_revision \
			or not _is_current_entry(generation) \
			or clock.get_total_elapsed_time() >= _TUTORIAL_CLOSE_TIMEOUT_SEC
	, presentation_revision)
	if clock.is_valid():
		clock.kill()
	if is_instance_valid(tutorial_page) and tutorial_page.tutorial_closed.is_connected(on_closed):
		tutorial_page.tutorial_closed.disconnect(on_closed)
	if not wait_completed or not _is_current_entry(generation):
		return
	_start_clock_after_tutorial()
	if not is_instance_valid(tutorial_page) or tutorial_page.get_presentation_revision() != tutorial_revision:
		return # 子页取消或被复用：恢复游戏即可，不能记为正常完成教程。
	# 只有原子页仍有效且真正发出 tutorial_closed 才记已看；超时只恢复游戏，不消耗教程资格。
	if not state["closed"]:
		push_error("DailyGamePage: dc_costume 教学页 tutorial_closed 超时未到,放行进关编排")
		return
	ProfileService.mark_costume_tutorial_shown()


func _life_capsule_for_tutorial() -> Control:
	return get_node_or_null("Root/VBoxContainer/CatHeartRow/HeartBg") as Control


## 停止文字计时心跳并按恢复基数重新锚定时间；教程占用的时长由结束后的再次锚定排除。
func _hold_clock_for_tutorial() -> void:
	_clock_timer.stop()
	_anchor_clock()


## 教程正常结束或子页取消后，按恢复基数重新锚定并启动每日显示计时。
func _start_clock_after_tutorial() -> void:
	_anchor_clock()
	_refresh_timer_label()
	_clock_timer.start()


## 关闭每日胜利页，以重玩参数重新进入每日页；重玩与未完成挑战的残局恢复有不同保存规则。
func _on_win_replay_requested() -> void:
	UIManager.hide_ui(UiName.DAILY_WIN)
	UIManager.show_ui(UiName.DAILY_GAME, DcReplayFlow.enter_params())


## 按当前局身份展示签到/补签结果；子流程和延迟持续检查父代次，取消后不继续打开后续窗口。
func _try_run_streak_flow_after_win(_source: StringName, skip_cat_appear: bool = false) -> bool:
	var generation: int = _business_generation
	var has_revive: bool = StreakManager.has_pending_revive_decision()
	if not has_revive and not StreakManager.has_pending_show():
		return false

	if not skip_cat_appear:
		var deadline: int = Time.get_ticks_msec() + int(DailyWinPage.APPEAR_DELAY * 1000.0)
		while Time.get_ticks_msec() < deadline and _is_current_entry(generation):
			await get_tree().process_frame
		if not _is_current_entry(generation):
			return false
	if has_revive:
		await StreakReviveFlow.run(self, func() -> bool: return _is_current_entry(generation))
		if not _is_current_entry(generation):
			return false
	if not StreakManager.has_pending_show():
		return true
	await StreakPage.open_after_win(func() -> bool: return _is_current_entry(generation))
	if not _is_current_entry(generation):
		return false
	return true


func _on_cheat_command(cmd_name: String, args: Array[String]) -> void:
	match cmd_name:
		"win":
			_cmd_win(args)
		"lives":
			_cmd_lives(args)
		"time":
			_cmd_time(args)

		"draft":
			_cmd_draft()
		"draft_win":
			_cmd_draft_win()


func _cmd_time(args: Array[String]) -> void:
	var sec: float = maxf(0.0, float(args[0]) if not args.is_empty() else 90.0)
	_start_unix = Time.get_unix_time_from_system() - sec
	_like_hand_state["in_game_sec"] = sec
	_refresh_timer_label()
	Toast.popup("当前时间已设为 %.1fs" % sec, self)


## 本局题目来自哪个题库（埋点用）：实验组看 use_gc_bank，控制组按等级分 regular / lkstyle
func _get_dc_bank_source(current_lv: int, day_offset: int) -> String:
	if ABTestManager.dc_level.is_override_enabled():
		var sz: int = ABTestManager.dc_level.get_pool_size(current_lv, day_offset)
		if ABTestManager.dc_level.use_gc_bank(sz, day_offset):
			return "gc"
		return "regular"
	return "lkstyle" if current_lv > 200 else "regular"


## 公历日期 → 儒略日序号，用来算两个日期差几天
static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


## 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME


func _current_round_time_sec() -> int:
	var time_sec: int = _level_config.get("elapsed_sec", 0)
	if time_sec <= 0:
		time_sec = _get_elapsed_sec()
	if time_sec == 0:
		time_sec = super._current_round_time_sec()
	return time_sec


func _build_game_end_params(result: String) -> Dictionary:
	var time_sec: int = _current_round_time_sec()

	var sz: int = _level_config.get("size", 0)
	var cat_n: int = _board_view.count_cat_cells()
	var params: Dictionary = {
		"qid": _build_qid(),
		"qrotate": Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
		"result": result,
		"game_type": Tracker.GameType.DAILY,
		"game_id": GameState.get_persisted_game_id(Tracker.GameType.DAILY),
		"diffi": _get_diffi(),
		"level": GameState.get_current_level(),
		"strategy_layer": _level_config.get("rank", 0),
		"scale": sz,
		"pre_cat_positions": "[]",
		"rating": _level_config.get("rating", 0.0),
		"hint": GameState.get_tool_count("hint"),
		"locate": GameState.get_tool_count("locate"),
		"hint_used": Tracker.get_stat("hint_used"),
		"locate_used": Tracker.get_stat("locate_used"),
		"hint_used_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "hint_used_total"),
		"locate_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "locate_used_total"),
		"mouse": GameState.get_tool_count(ToolKind.MOUSE),
		"mouse_used": Tracker.get_stat("mouse_used"),
		"mouse_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "mouse_used_total"),
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
		"draft_apply_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_apply_used_total"),
		"draft_stop_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_stop_used_total"),
		"coord_count": Tracker.get_stat("coord_count"),
		"step_used": Tracker.get_stat("step_used"),
		"step_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "step_total"),
		"cat_click_num": Tracker.get_stat("cat_click_num"),
		"gamedie_count": Tracker.get_stat("gamedie_count"),
		"restart_count": Tracker.get_stat("restart_count"),
		"time": time_sec,
		"time_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "time_total"),
		"percent": _level_config.get("beat_percent", 0.0),
		"cross_count": _board_view.count_mark_cells(),
		"correct_cross_count": _count_correct_crosses(),
		"false_cross_count": _count_false_crosses(),
		"hint_cross_count": Tracker.get_stat("hint_cross_count"),
		"invalid_sign": _board_view.count_error_cells(),
		"invalid_sign_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "invalid_sign_total"),
		"fail_sign": sz - cat_n,
		"erase_count": Tracker.get_stat("erase_count"),
		"revive_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "revive_count"),
		"rv_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "rv_count"),
		"hp_count": _lives,
		"se_score": _score_model.score,
		"is_tap_cat_at_last": _last_cat_at_last_flag(),
	}
	print(
		(
			"[DailyGamePage] game_end cross: correct=%d false=%d hint=%d | cross_count=%d invalid_sign=%d"
			% [
				params["correct_cross_count"],
				params["false_cross_count"],
				params["hint_cross_count"],
				params["cross_count"],
				params["invalid_sign"]
			]
		)
	)
	print(
		(
			"[DailyGamePage] game_end step: step_used=%d step_total=%d | locate_used=%d hint_apply_used=%d"
			% [
				params["step_used"],
				params["step_total"],
				params["locate_used"],
				params["hint_apply_used"]
			]
		)
	)
	print(
		(
			"[DailyGamePage] game_end last_cat: is_tap_cat_at_last=%d | streak=%d/%d cross@1st=%d/阈%d"
			% [
				params["is_tap_cat_at_last"],
				_cat_streak,
				sz,
				_cross_at_first_cat,
				LastCatJudge.cross_threshold(sz)
			]
		)
	)
	params.merge(_ELO_END_EXTRA_PLACEHOLDER)
	params.merge(_companion_game_end_fields(false))
	return params


func _cat_progress_default_path() -> String:
	return "Root/VBoxContainer/CatProgressRow/CatProgressBar"


func _cat_progress_adjacent_path() -> String:
	return "Root/VBoxContainer/BoardContainer/CatProgressBar"


func _cat_progress_adjacent_holder_path() -> String:
	return "Root/VBoxContainer/AdjacentBoardBarHolder"


func _function_area_min_h_for_adjacent_bar() -> float:
	return -1.0


func _set_cat_progress_row_visible(on: bool) -> void:
	var holder: Control = get_node_or_null("Root/VBoxContainer/CatProgressAdaptHolder") as Control
	var row: Control = get_node_or_null("Root/VBoxContainer/CatProgressRow") as Control
	if holder != null:
		holder.visible = on
	if row != null:
		row.visible = on

	_refresh_short_screen_compaction()


func _cat_progress_default_metrics(total: int) -> Dictionary:
	var metrics: Dictionary = CatProgressBar.solve_metrics(total, 0.0)
	metrics["align"] = "center"
	return metrics


func _cat_progress_band_top() -> float:
	var candidates: Array = [
		"Root/VBoxContainer/CatHeartRow/HeartBg",
		"Root/VBoxContainer/CatHeartRow/TimeContainer",
	]
	var bottom: float = 0.0
	var found: bool = false
	for path: String in candidates:
		var node: Control = get_node_or_null(String(path)) as Control
		if node == null or not node.visible:
			continue
		bottom = (
			maxf(bottom, node.get_global_rect().end.y) if found else node.get_global_rect().end.y
		)
		found = true
	if found:
		return bottom
	var row: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow") as Control
	return row.get_global_rect().end.y if row != null else 0.0


func _center_cat_progress_vertically() -> void:
	if _cat_progress == null or not _cat_progress.visible:
		return

	if _cat_progress_uses_adjacent_bar():
		return
	var row: Control = _cat_progress.get_parent() as Control
	var rules_bg: Control = (
		get_node_or_null("Root/VBoxContainer/RuleBar/Control/RulesBg") as Control
	)
	if row == null or rules_bg == null:
		return
	var band_top: float = _cat_progress_band_top()
	var band_bottom: float = rules_bg.get_global_rect().position.y
	var bar_height: float = _cat_progress.size.y
	var gap: float = (band_bottom - band_top - bar_height) * 0.5

	if gap < 0.0:
		return
	var wanted_top: float = band_top + gap - row.get_global_rect().position.y

	if is_equal_approx(_cat_progress.offset_top, wanted_top):
		return
	_cat_progress.offset_top = wanted_top
	_cat_progress.offset_bottom = wanted_top + bar_height


func _layout_cat_progress_bar(metrics: Dictionary) -> void:
	super._layout_cat_progress_bar(metrics)
	_relayout_cat_heart_row_for_progress()
	_center_cat_progress_vertically()


func _relayout_cat_heart_row_for_progress() -> void:
	if _cat_progress == null or not _cat_progress.visible:
		return
	_apply_heart_bg_position_for_progress(true)


func _apply_heart_bg_position_for_progress(cat_bar: bool = false) -> void:
	var row: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow") as Control

	var row_width: float = row.size.x if row != null and row.size.x > 0.0 else 1080.0
	var pairs: Array = [
		["Root/VBoxContainer/CatHeartRow/HeartBg", -285.0, -25.0],
		["Root/VBoxContainer/CatHeartRow/TimeContainer", 25.0, 285.0],
	]
	for p: Array in pairs:
		var node: Control = get_node_or_null(String(p[0])) as Control
		if node == null:
			continue
		if not node.has_meta("_cp_base_l"):
			node.set_meta("_cp_base_l", node.offset_left)
			node.set_meta("_cp_base_r", node.offset_right)
		if cat_bar:
			var anchor_shift: float = (0.5 - node.anchor_left) * row_width
			node.offset_left = float(p[1]) + anchor_shift
			node.offset_right = float(p[2]) + anchor_shift
		else:
			node.offset_left = float(node.get_meta("_cp_base_l"))
			node.offset_right = float(node.get_meta("_cp_base_r"))


const _SHORT_SCREEN_MIN_H: Dictionary = {
	"RuleBarAdaptHolder": 6.0,
	"BoardAdaptHolder": 6.0,
	"FunctionAdaptHolder": 0.0,
	"FunctionArea": 4.0,
	"AdAdaptHolder": 6.0,
}

var _short_screen_applied: bool = false


func _refresh_short_screen_compaction() -> void:
	var vbox: Control = get_node_or_null("Root/VBoxContainer") as Control
	if vbox == null:
		return

	_set_short_screen_compaction(false)
	if not _cat_progress_adds_vbox_height():
		return
	var parent: Control = vbox.get_parent() as Control
	if parent == null:
		return

	var avail: float = (
		parent.size.y * (vbox.anchor_bottom - vbox.anchor_top)
		+ vbox.offset_bottom
		- vbox.offset_top
	)
	if vbox.get_combined_minimum_size().y <= avail:
		return
	_set_short_screen_compaction(true)


func _cat_progress_adds_vbox_height() -> bool:
	var row: Control = get_node_or_null("Root/VBoxContainer/CatProgressRow") as Control
	if row != null and row.visible:
		return true
	var holder_path: String = _cat_progress_adjacent_holder_path()
	if holder_path.is_empty():
		return false
	var holder: Control = get_node_or_null(NodePath(holder_path)) as Control
	return holder != null and holder.visible


func _set_short_screen_compaction(on: bool) -> void:
	if on == _short_screen_applied:
		return
	var node_names: Array = _SHORT_SCREEN_MIN_H.keys()
	for node_name: String in node_names:
		var node: Control = get_node_or_null("Root/VBoxContainer/" + node_name) as Control
		if node == null:
			continue
		if not node.has_meta("_ss_base_min_h"):
			node.set_meta("_ss_base_min_h", node.custom_minimum_size.y)
		node.custom_minimum_size.y = (
			float(_SHORT_SCREEN_MIN_H[node_name]) if on else float(node.get_meta("_ss_base_min_h"))
		)
	_short_screen_applied = on


## 按日期偏移选择题池及八种变换，逐个跳过非法题面；全部候选都失败时返回 false，不能复用上一局题目。
func _prepare_daily_puzzle(current_lv: int, day_offset: int) -> bool:
	# 页面会缓存复用；先清本次准备字段，整池失败时不能泄露上一局题面为新题。
	_puzzle = {}
	_level_config = {}
	# 每道题有 8 种等价变换（镜像 × 4 个旋转）。
	const TRANSFORM_COUNT: int = 8
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

	if not ContentContext.content_error().is_empty():
		_report_business_failure(ContentContext.content_error())
		return false

	# 题库为空属于配置错误，直接报错退出
	if pool.is_empty():
		push_error("DailyGamePage: 无可用关卡（current_lv=%d）" % current_lv)
		return false

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
		entry = BankData.materialize_entry(pool[entry_idx])
		if not DailyEndgameSnapshot.puzzle_entry_is_valid(entry, sz):
			virtual_idx = (virtual_idx + 1) % total_virtual
			transform = virtual_idx / pool_size
			entry_idx = virtual_idx % pool_size
			attempts += 1
			continue
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
		# 旋转假定答案每列唯一；先拒绝原始非法题，避免变换制造空列或越界。
		if QueendokuCore.validate_solution_entry(
			{"regionMap": int_regions, "solution": sol_1d}, sz
		):
			# 变换 0 是原题，另外 7 种是镜像/旋转出来的等价题面。
			if transform > 0:
				var transformed: Array = LevelData.apply_transform(int_regions, sol_1d, sz, transform)
				int_regions = transformed[0]
				sol_1d = transformed[1]
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
	# 整池都不合法时拒绝开局，不能把最后一份非法题面交给棋盘。
	if attempts >= total_virtual:
		_report_business_failure({"logical_id": "doku/daily", "error": "no_valid_puzzle"})
		return false

	# R1~R5 五层提示策略的步数也来自题库记录
	_strategy_steps[0] = int(entry.get("r1", 0))
	_strategy_steps[1] = int(entry.get("r2", 0))
	_strategy_steps[2] = int(entry.get("r3", 0))
	_strategy_steps[3] = int(entry.get("r4", 0))
	_strategy_steps[4] = int(entry.get("r5", 0))

	# 正式包（rel 特性）里藏掉策略按钮
	if _strategy_btn != null:
		_strategy_btn.visible = OS.is_debug_build() and not OS.has_feature("rel")

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
		"rating": entry.get("rating", 0.0),
	}
	_puzzle = {"regions": int_regions, "solution": sol_2d}
	_round_content_provenance = {"table": entry.get("_content_provenance", {}).duplicate(true), "policy": DokuPolicy.provenance()}

	return true

## 递增按钮锁序号，断开旧入场完成信号并停动画；旧解锁回调即使稍后返回也不能接管新一轮入口。
func _stop_entry_animation() -> void:
	_entry_btn_lock_seq += 1
	_entry_anim_playing = false
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		if board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)
		board_intro.set_process(false)
	if _anim_player.is_playing():
		_anim_player.stop()
	_unlock_entry_buttons()


## 返回会话提交时携带的每日兼容快照；关闭保存、重玩、调试或无题面时返回空字典。
func _business_checkpoint() -> Dictionary:
	if not ABTestManager.dc_endgame_save.is_enabled() or _stat_status == Tracker.GameStatus.REPLAY or DailyGamePage.debug_day_override >= 0 or _puzzle.is_empty():
		return {}
	return _build_endgame_snapshot()


## 防抖之外的延迟写入只接受当前业务代次，旧局通知在重开后直接丢弃。
func _flush_endgame_for_generation(generation: int) -> void:
	if _is_current_entry(generation):
		_flush_endgame_snapshot()


## 先提交当前每日尝试的退出，成功后清理表现并以 RESTART 再入场；失败不提前清空当前局。
func _restart_daily_round(context: Dictionary) -> void:
	var settlement_id: String = _business_settlement_id()
	if not _is_current_round_transition(context):
		return
	var settled: bool = not settlement_id.is_empty() and LevelOps.confirm_level_failed_daily(_build_game_end_params(Tracker.GameResult.QUIT), settlement_id, _start_date, _business_runtime())
	if not _is_current_round_transition(context):
		return
	# 退出结算失败时仍保留当前棋盘；成功才清页面分数并准备新的每日尝试。
	if not settled:
		_report_business_failure({"error": "settlement_failed"})
		return
	_reset_game_barrages()
	_score_model.reset_all()
	_se_count = 0
	_exit_draft_mode_and_clear()
	if not _is_current_round_transition(context):
		return

	_destroy_banner()
	if not _is_current_round_transition(context):
		return

	on_show({"_tracker_status": Tracker.GameStatus.RESTART})


## 把本局猫/标记增量、服装资格与用时交给每日结算服务；页面只提供输入，不自行累加这些奖励事实。
func _daily_settlement_context() -> Dictionary:
	return {"today_cat_delta": _board_view.count_cat_cells(), "today_mark_delta": today_mark_cell_count(),
		"pass_text": int(ABTestManager.pass_text.value()), "costume_id": _in_game_costume_id,
		"unlock_costume": ABTestManager.dc_costume.has_costume() and _lives >= 3,
		"game_time_sec": _current_round_time_sec()}
