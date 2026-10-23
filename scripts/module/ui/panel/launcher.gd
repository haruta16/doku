## 启动协调节点：依次准备语言字体、原生服务、授权、账号数据和页面资源，再进入主页或教程。
## 账号切换使用两段式软重载：先展示闪屏，数据合并结束后再重建落地页面。
extends Node

const _SPLASH_SCENE: PackedScene = preload("res://scripts/module/splash/ui/splash_page.tscn") # 闪屏页场景：提前 preload；实际显示走 UIManager 的注册表，这里目前只是一份冗余引用

const _STARTUP_SYNC_TIMEOUT_MS: int = 5000

const _RELOAD_ROUTE_FALLBACK_MS: int = 45000

# ---- 启动期运行时状态 ----
var _splash_page = null # 闪屏页实例（由 UIManager 创建），收尾时对它 force_complete
var _startup_complete: bool = false # 冷启动是否走完；走完才允许响应快捷方式与前台事件

var _reload_route_pending: bool = false

var _reload_done_count: int = 0
var _reload_dropped_count: int = 0
var _reload_fallback_count: int = 0

var _crashlytics_logger: LogUtil = null # 把 Godot 日志转发给 Crashlytics 的 Logger

var _in_game_log_buffer: InGameLogBuffer = null # 内存日志缓冲，作弊面板「日志」页的数据源

var _cheat_commands: Node = null

# ---- 启动性能埋点（毫秒时间戳） ----
var _perf_t0: int = 0 # 启动开始时刻
var _perf_last: int = 0 # 上一步的时刻，用来算单步耗时
var _perf_emitted: Dictionary = {} # 已上报的 step 去重表


# ================= 启动性能埋点 =================
## 上报一个启动阶段耗时；同一步只上报一次，重复调用直接忽略
func _emit_perf(step: String) -> void:
	# 已报过就不再发，避免超时兜底与事件竞态导致重复埋点
	if _perf_emitted.has(step):
		return
	_perf_emitted[step] = true
	# cost＝距上一步，total＝距启动开始
	var now: int = Time.get_ticks_msec()
	Tracker.track_perf_monitor("app_start", step, now - _perf_last, now - _perf_t0)
	_perf_last = now


## 记录加载页首帧真正提交绘制的时间，供冷启动性能排查。
func _probe_loading_presented() -> void:
	print("[BootProbe] loading_page_presented=%dms" % Time.get_ticks_msec())


## 串联冷启动流程：接入日志与事件、等待授权及账号状态、预热资源，再完成首屏路由。
func _ready() -> void:
	_crashlytics_logger = LogUtil.new()
	OS.add_logger(_crashlytics_logger)

	if not OS.has_feature("rel"):
		_in_game_log_buffer = InGameLogBuffer.new()
		InGameLogBuffer.instance = _in_game_log_buffer
		OS.add_logger(_in_game_log_buffer)

	Engine.max_fps = 60

	DisplayServer.screen_set_keep_on(true)

	UIManager.apply_design_canvas()

	_perf_t0 = Time.get_ticks_msec()
	_perf_last = _perf_t0

	print("[BootProbe] engine+autoload=%dms" % _perf_t0)

	LanguageManager.apply_system_locale()

	FontSwapManager.apply()

	ABTestManager.font_test_en.debug_override_changed.connect(FontSwapManager.apply)
	ABTestManager.font_test_zh.debug_override_changed.connect(FontSwapManager.apply)
	ABTestManager.font_test_jp.debug_override_changed.connect(FontSwapManager.apply)

	SessionManager.session_changed.connect(_on_session_changed)

	AccountManager.page_reload_requested.connect(_reload_to_target_page)

	AccountManager.reload_presentation_requested.connect(_begin_reload_presentation)
	AccountManager.reload_route_requested.connect(_finish_reload_to_target)

	GameState.consume_first_session_persist()

	if not OS.has_feature("rel"):
		var overlay_scene: PackedScene = load("res://scripts/module/cheat/ui/cheat_overlay.tscn")
		var overlay: Node = overlay_scene.instantiate()
		overlay.commands_requested.connect(_mount_cheat_commands)
		add_child(overlay)

	print(
		(
			"[BootProbe] cheat_mounted=%dms mounted=%s"
			% [Time.get_ticks_msec(), str(not OS.has_feature("rel"))]
		)
	)

	if OS.has_feature("android"):
		await get_tree().create_timer(1.0).timeout

	print("[BootProbe] native_splash_wait_done=%dms" % Time.get_ticks_msec())

	_splash_page = UIManager.show_ui(UiName.SPLASH)

	print("[BootProbe] splash_created=%dms" % Time.get_ticks_msec())

	RenderingServer.frame_post_draw.connect(_probe_loading_presented, CONNECT_ONE_SHOT)

	_hide_native_splash(500)

	_emit_perf(Tracker.PerfStep.LOAD_SPLASH)

	ShortcutManager.add_shortcuts(tr("SHORTCUT_FEEDBACK_TITLE"), tr("SHORTCUT_IMPORTANT_TITLE"))

	ShortcutManager.connect_shortcut_received(_on_shortcut_received_pushed)

	_initialize_unikit_sdk()

	await ABTestManager.init_success()

	if UniKitManager.check_privacy_required():
		var privacy_ui: StringName = UiName.PRIVACY
		match ABTestManager.privacy_pop.value():
			PrivacyPopConfig.VALUE_V2_UI:
				privacy_ui = UiName.PRIVACY_V2
			PrivacyPopConfig.VALUE_V3_UI:
				privacy_ui = UiName.PRIVACY_V3
			_:
				privacy_ui = UiName.PRIVACY
		var privacy_dialog: Node = UIManager.show_ui(privacy_ui)

		GameState.mark_startup_permission_prompt_shown()

		print("[Launcher] 隐私弹窗已展示，等待用户同意")
		await privacy_dialog.accepted
		UIManager.hide_ui(privacy_ui)
		UniKitManager.agree_privacy()
		print("[Launcher] 隐私已同意")
	else:
		print("[Launcher] 跳过隐私弹窗（SDK 判定无需）")

	UniKitManager.init_att()

	print(
		(
			"[Push] launcher: push_ask_count=%d, is_android=%s, is_ios=%s"
			% [GameState.get_push_ask_count(), OS.has_feature("android"), OS.has_feature("ios")]
		)
	)

	var push_unlock: int = ABTestManager.push_unlock_level.unlock_level()
	var push_level_ok: bool = push_unlock <= 0 or GameState.get_current_level() >= push_unlock
	if (
		(OS.has_feature("android") or OS.has_feature("ios"))
		and GameState.get_push_ask_count() < 2
		and push_level_ok
	):
		var ask_seq: int = GameState.get_push_ask_count() + 1
		if await UniKitManager.can_request_permission(UniKitManager.PUSH_PERMISSION_TYPE_SYSTEM):
			print("[Push] launcher: 发起第 %d 次请求" % ask_seq)

			GameState.mark_startup_permission_prompt_shown()
			UniKitManager.request_push_permission()
			await UniKitManager.push_permission_done
		else:
			print(
				"[Push] launcher: can_request_permission(SYSTEM)=false(已授权/已拒绝/Android<13),跳过 SDK 请求"
			)
		GameState.inc_push_ask_count()
		print(
			(
				"[Push] launcher: 第 %d 次请求结束,push_ask_count 更新为 %d"
				% [ask_seq, GameState.get_push_ask_count()]
			)
		)
	elif not push_level_ok:
		print(
			(
				"[Push] launcher: 跳过请求(push_unlock_level=%d,current_level=%d 未达标,不 inc 不设冷却)"
				% [push_unlock, GameState.get_current_level()]
			)
		)
	else:
		print("[Push] launcher: 跳过请求(平台不符或 push_ask_count 已达上限)")

	UniKitManager.set_push_enabled(true)
	_clear_daily_pushes()
	var _do_register_push := func():
		await get_tree().create_timer(0.5).timeout
		print("[Push] _register_daily_pushes 执行（APP_START 染色已就绪）")
		_register_daily_pushes()

		StreakPushScheduler.reevaluate("cold_start")
		StreakManager.streak_updated.connect(
			func(_data: StreakData) -> void: StreakPushScheduler.reevaluate("streak_updated"),
			CONNECT_REFERENCE_COUNTED
		)
	if ABTestManager.is_app_start_dyed():
		print("[Push] APP_START 染色已就绪，直接注册 push")
		_do_register_push.call()
	else:
		print("[Push] APP_START 染色未就绪，等待 init_done 信号后注册 push")
		ABTestManager.init_done.connect(_do_register_push, CONNECT_ONE_SHOT)

	await get_tree().process_frame

	await _wait_cmp_then_att_max_2s()

	if UniKitManager.is_analyze_inited():
		_bind_crashlytics_user_id()
	else:
		UniKitManager.analyze_init_completed.connect(_bind_crashlytics_user_id, CONNECT_ONE_SHOT)

	ScreenManager.setup()

	RankActivityManager.set_first_frame_tiered(ABTestManager.rank_1st_frame.is_enabled())

	RankActivityManager.set_streak_rule(
		ABTestManager.rank_win.streak_table(),
		ABTestManager.rank_win.boost_spec(),
		ABTestManager.rank_win.x_base_rule()
	)

	await SoundManager.warmup_sfx()
	await _prewarm_game()
	await _prewarm_home()
	await _prewarm_daily()

	await AccountManager.await_startup_settled(_STARTUP_SYNC_TIMEOUT_MS)
	await _prewarm_activity_pages()

	var _do_dye_level_reach_51 := func() -> void:
		_clear_golden_fish_on_form_switch()

		_clear_color_challenge_on_form_switch()
		_clear_onefish_on_timing_switch()
	if ABTestManager.is_ab_init_done():
		_do_dye_level_reach_51.call()
	else:
		ABTestManager.init_done.connect(_do_dye_level_reach_51, CONNECT_ONE_SHOT)

	await _wait_splash_complete()

	_emit_perf(Tracker.PerfStep.END)

	_read_streak_push_click()

	await _route_to_target_page(true)
	_startup_complete = true

	print("[Launcher] 冷启动完成（软重载闸门已开）")


## 仅在首次打开调试入口时实例化命令节点，避免启动就加载整套调试逻辑。
func _mount_cheat_commands() -> void:
	if _cheat_commands != null and is_instance_valid(_cheat_commands):
		return
	var commands_script: GDScript = load("res://scripts/module/cheat/cheat_commands.gd")
	_cheat_commands = commands_script.new()
	add_child(_cheat_commands)


## 等待异步页面加载结束，按快捷入口、教程进度和回流欢迎状态选择落地页，最后关闭闪屏。
func _route_to_target_page(allow_shortcut: bool) -> void:
	while UIManager.is_any_loading():
		await get_tree().process_frame

	UIManager.close_async_warm_window()

	FontSwapManager.apply()

	if allow_shortcut:
		RankActivityManager.set_reopen_wins(ABTestManager.leaderboard_reopen_timing.reopen_wins())
	if allow_shortcut and _try_handle_shortcut():
		pass
	elif GameState.is_tutorial_done():
		if allow_shortcut:
			var cheat_group: int = ComebackCheat.consume_next_cold_start()
			if cheat_group >= 0:
				ABTestManager.comeback_func.set_debug_override(cheat_group)
				print("[Comeback] cheat:本次冷启动 comeback_func 按 %d 处理" % cheat_group)
		if ABTestManager.comeback_func.should_play_welcome(
			allow_shortcut,
			GameState.get_login_gap_days(),
			true,
			GameState.is_comeback_welcome_shown()
		):
			await _play_comeback_welcome()
		UIManager.show_ui(UiName.HOME)
	else:
		UIManager.show_ui(UiName.TUTORIAL)

	UIManager.hide_ui(UiName.SPLASH)


## 预触发当前关难度判断后展示回流欢迎页，等待其隐藏才继续启动路由。
func _play_comeback_welcome() -> void:
	LevelSelector.is_hard_level(GameState.get_current_level())
	UIManager.show_ui(UiName.COMEBACK_WELCOME)
	UIManager.hide_ui(UiName.SPLASH)
	await UIManager.await_hidden(UiName.COMEBACK_WELCOME)


## 冷启动结束后才能软重载；关闭其他页面、等待闪屏结束，再按当前账号状态路由。
func _reload_to_target_page() -> void:
	if not _startup_complete:
		_reload_dropped_count += 1
		push_warning("[Launcher] 软重载请求被忽略：冷启动尚未完成（页栈不会重建，UI 会留在旧账号态）")
		return
	print("[Launcher] 软重载：回 splash 重新加载数据")
	_splash_page = UIManager.show_ui(UiName.SPLASH)

	await UIManager.hide_all_showing_except([UiName.SPLASH])
	await _wait_splash_complete()
	await _route_to_target_page(false)
	_reload_done_count += 1
	print("[Launcher] 软重载完成")


## 两段式重载先展示闪屏并关闭旧页面，最多等待 45 秒后自动执行后半段。
func _begin_reload_presentation() -> void:
	if not _startup_complete:
		_reload_dropped_count += 1
		push_warning("[Launcher] 两段式软重载·前半段被忽略：冷启动尚未完成（不进 splash，且业务侧遮罩已被抑制）")
		return
	print("[Launcher] 两段式软重载·前半段：进 splash（表现），等业务侧跑完合并")
	_reload_route_pending = true
	_splash_page = UIManager.show_ui(UiName.SPLASH)
	await UIManager.hide_all_showing_except([UiName.SPLASH])

	var armed_at: int = Time.get_ticks_msec()
	while _reload_route_pending and Time.get_ticks_msec() - armed_at < _RELOAD_ROUTE_FALLBACK_MS:
		await get_tree().process_frame
	if _reload_route_pending:
		_reload_fallback_count += 1
		push_warning("[Launcher] 两段式软重载·后半段迟迟未来(%dms)，兜底直接路由" % _RELOAD_ROUTE_FALLBACK_MS)
		await _finish_reload_to_target()


## 消费待路由标记，等待闪屏表现结束并进入目标页；缺少前半段的请求会被丢弃。
func _finish_reload_to_target() -> void:
	if not _startup_complete:
		_reload_dropped_count += 1
		push_warning("[Launcher] 两段式软重载·后半段被忽略：冷启动尚未完成（合并已落地，但不回 splash、不重建页栈）")
		return
	if not _reload_route_pending:
		_reload_dropped_count += 1
		push_warning("[Launcher] 两段式软重载·后半段被忽略：没有待路由的前半段（present / route 未成对）")
		return
	_reload_route_pending = false
	print("[Launcher] 两段式软重载·后半段：等 splash 表现走完 → 路由")
	await _wait_splash_complete()
	await _route_to_target_page(false)
	_reload_done_count += 1
	print("[Launcher] 两段式软重载完成")


## 返回冷启动完成状态，以及软重载成功、丢弃和超时兜底次数。
func get_reload_stats() -> Dictionary:
	return {
		"startup_complete": _startup_complete,
		"reload_route_pending": _reload_route_pending,
		"done": _reload_done_count,
		"dropped": _reload_dropped_count,
		"fallback": _reload_fallback_count,
	}


## 比较前后实验组的金鱼关形态，变化时清掉不再适用的计数、待触发状态、锁题和残局。
func _clear_golden_fish_on_form_switch() -> void:
	var gf: GoldenFishFuncConfig = ABTestManager.golden_fish_func
	var host: NormalLevelConfig = ABTestManager.normal_level
	if gf == null or host == null:
		return
	var enabled: bool = gf.is_enabled()
	var cur_form: int = GoldenFishGate.current_form(enabled)

	var prev_gf: int = gf.get_prev_saved_group()

	var prev_form: int = (
		GoldenFishGate.form_from_group_value(prev_gf)
		if prev_gf >= 0
		else host.golden_fish_prev_group()
	)

	if not OS.has_feature("rel"):
		print(
			(
				"[GoldenFish] 形态闸门: gf_prev=%d host_prev=%d → prev_form=%d, cur_form=%d(enabled=%s) → %s"
				% [
					prev_gf,
					host.golden_fish_prev_group(),
					prev_form,
					cur_form,
					str(enabled),
					(
						"要清"
						if GoldenFishGate.should_clear_on_form_switch(prev_form, cur_form)
						else "不清"
					)
				]
			)
		)
		var snap: Dictionary = GameState.get_endgame_snapshot()
		print(
			(
				"[GoldenFish] 当前残局快照: %s"
				% (
					"空"
					if snap.is_empty()
					else (
						"level=%s kind=%s(一命关=%s)"
						% [
							str(snap.get("level", "?")),
							str(snap.get("kind", "?")),
							str(LevelKind.is_golden_fish(int(snap.get("kind", 1))))
						]
					)
				)
			)
		)
		print(
			(
				"[GoldenFish] pending=%s 频率计数=%d retry锁来源=%s"
				% [
					str(GameState.get_golden_fish_pending()),
					GameState.get_golden_fish_streak_count(),
					str(
						GameState.get_retry_puzzle(GameState.get_current_level()).get(
							"bank_source", "无锁"
						)
					)
				]
			)
		)
	if not GoldenFishGate.should_clear_on_form_switch(prev_form, cur_form):
		_clear_onefish_retry_on_pick_switch(prev_gf, gf)
		return

	var snap_before: Dictionary = GameState.get_endgame_snapshot()
	GameState.clear_golden_fish_state()
	_clear_stale_endgame_on_form_switch(
		snap_before, enabled, ABTestManager.golden_fish_timing.unlock_min_level()
	)

	gf.consume_switch()
	print("[GoldenFish] 切形态 %d → %d,已清一命关残余状态(计数/pending/残局/锁题)" % [prev_form, cur_form])


## 金鱼关仍开启但取题组改变时，清锁题和残局，让下次进入按新策略重抽。
func _clear_onefish_retry_on_pick_switch(prev_gf: int, gf: GoldenFishFuncConfig) -> void:
	var cur_gf: int = int(gf.peek_value())

	if prev_gf < GoldenFishFuncConfig.VALUE_ON or cur_gf < GoldenFishFuncConfig.VALUE_ON:
		return
	if prev_gf == cur_gf:
		return
	GameState.clear_onefish_retry_puzzle_on_pick_switch()

	gf.consume_switch()
	print("[GoldenFish] 取题策略切组 %d → %d,已清一命关锁题 + 残局(进那关会按新策略重抽一道)" % [prev_gf, cur_gf])


## 频率实验组切换时重置触发计数；当前关号不满足新门槛时进一步清掉金鱼关残留。
func _clear_onefish_on_timing_switch() -> void:
	var timing: GoldenFishTimingConfig = ABTestManager.golden_fish_timing
	if timing == null:
		return
	var prev: int = timing.get_prev_saved_group()
	var cur: int = timing.current_group()
	if prev < 0 or prev == cur:
		return
	GameState.clear_onefish_timing_state()
	var min_level: int = timing.unlock_min_level()
	var lv: int = GameState.get_current_level()
	if lv < min_level:
		var snap_before: Dictionary = GameState.get_endgame_snapshot()
		GameState.clear_golden_fish_state()
		_clear_stale_endgame_on_form_switch(
			snap_before, ABTestManager.golden_fish_func.is_enabled(), min_level
		)
		print(
			"[GoldenFish] timing 切组 %d → %d:当前关号 %d 够不上新门槛 %d,已清一命关残余" % [prev, cur, lv, min_level]
		)
	else:
		print(
			(
				"[GoldenFish] timing 切组 %d → %d:频率状态已重置(关号 %d ≥ 门槛 %d,残余保留)"
				% [prev, cur, lv, min_level]
			)
		)

	timing.consume_switch()


## 只在金鱼形态规则认定快照不兼容时清残局，避免恢复到旧玩法状态。
func _clear_stale_endgame_on_form_switch(snap: Dictionary, enabled: bool, min_level: int) -> void:
	if snap.is_empty():
		return
	var snap_level: int = int(snap.get("level", 0))
	if snap_level <= 0:
		return
	var snap_kind: int = int(snap.get("kind", LevelKind.default_kind()))

	if not GoldenFishGate.should_clear_endgame_on_switch(
		snap_kind, snap_level, false, enabled, min_level
	):
		return
	GameState.clear_endgame_snapshot()
	print(
		(
			"[GoldenFish] 切形态后残局 kind 与本次形态不符(level=%d 快照kind=%d enabled=%s 门槛=%d),已清残局"
			% [snap_level, snap_kind, str(enabled), min_level]
		)
	)


## 颜色挑战形态切组时清掉旧待触发状态、锁题和色盲快照，再消费切组标记。
func _clear_color_challenge_on_form_switch() -> void:
	var cfg: ColorChallengeFuncConfig = ABTestManager.color_challenge_func
	if cfg == null:
		return
	var cur_form: int = ColorChallengeGate.current_form(cfg.group_value())
	var prev_form: int = cfg.get_prev_saved_group()

	if not OS.has_feature("rel"):
		var snap: Dictionary = GameState.get_endgame_snapshot()
		print(
			(
				"[ColorChallenge] 形态闸门: prev_form=%d cur_form=%d → %s"
				% [
					prev_form,
					cur_form,
					(
						"要清"
						if ColorChallengeGate.should_clear_on_form_switch(prev_form, cur_form)
						else "不清"
					)
				]
			)
		)
		print(
			(
				"[ColorChallenge] 残局=%s pending=%s since_gf=%d 连续跳过=%d 防打扰目标关=%d 锁来源=%s"
				% [
					(
						"空"
						if snap.is_empty()
						else (
							"level=%s kind=%s"
							% [str(snap.get("level", "?")), str(snap.get("kind", "?"))]
						)
					),
					str(GameState.get_color_challenge_pending()),
					GameState.get_color_challenge_since_gf(),
					GameState.get_color_challenge_skip_count(),
					GameState.get_color_challenge_defer_until(),
					str(
						GameState.get_retry_puzzle(GameState.get_current_level()).get(
							"bank_source", "无锁"
						)
					)
				]
			)
		)
	if not ColorChallengeGate.should_clear_on_form_switch(prev_form, cur_form):
		return

	var snap_before: Dictionary = GameState.get_endgame_snapshot()
	var reset_skip: bool = ColorChallengeGate.should_reset_skip_count_on_switch(prev_form, cur_form)
	GameState.clear_color_challenge_state(reset_skip)
	_clear_stale_cc_endgame_on_form_switch(snap_before, cfg.group_value())

	cfg.consume_switch()
	print(
		(
			"[ColorChallenge] 切形态 %d → %d,已清颜色挑战残余(pending/残局/锁题/色盲快照%s)"
			% [prev_form, cur_form, "/跳过计数" if reset_skip else ""]
		)
	)


## 检查颜色挑战残局是否仍适用当前实验组，不适用时删除快照。
func _clear_stale_cc_endgame_on_form_switch(snap: Dictionary, group: int) -> void:
	if snap.is_empty():
		return
	var snap_level: int = int(snap.get("level", 0))
	if snap_level <= 0:
		return
	var snap_kind: int = int(snap.get("kind", LevelKind.default_kind()))

	if not ColorChallengeGate.should_clear_endgame_on_switch(snap_kind, snap_level, false, group):
		return
	GameState.clear_endgame_snapshot()
	print(
		(
			"[ColorChallenge] 切形态后残局 kind 与本次分组不符(level=%d 快照kind=%d group=%d),已清残局"
			% [snap_level, snap_kind, group]
		)
	)


## 今日挑战仍可参与时，异步预热每日页和十阶棋盘。
func _prewarm_daily() -> void:
	if DailyEntryState.is_done_like(DailyEntryState.compute_state()):
		return
	await UIManager.warm_pool_async(UiName.DAILY_GAME)
	var daily: Node = UIManager.get_ui(UiName.DAILY_GAME)
	if daily != null and daily.has_method("prewarm_board"):
		await daily.prewarm_board(_DAILY_PREWARM_SIZE)


const _DAILY_PREWARM_SIZE: int = 10


## 异步建立主页缓存，把首次实例化成本放到闪屏期间。
func _prewarm_home() -> void:
	await UIManager.warm_pool_async(UiName.HOME)


## 根据活动进度、待领奖和领奖台实验，预热下一步可能展示的活动页面。
func _prewarm_activity_pages() -> void:
	if RankActivityManager.is_running():
		await UIManager.warm_pool_async(
			(
				UiName.RANK_ACTIVITY_CHANGE_V2
				if ABTestManager.podium_per_game.is_list_podium_style()
				else UiName.RANK_ACTIVITY_CHANGE
			)
		)
	if not RankActivityManager.get_pending_reward().is_empty():
		await UIManager.warm_pool_async(UiName.AWARD)

	if (
		ABTestManager.podium_per_leaderboard.has_end_solo_podium()
		and (
			RankActivityManager.is_running()
			or not RankActivityManager.get_pending_end_solo_podium().is_empty()
		)
	):
		await UIManager.warm_pool_async(UiName.RANK_ACTIVITY_SOLO_PODIUM)


## 预热普通游戏页、选题策略、棋盘和当前尺寸题库；需要节奏排序时一并加载节奏数据。
func _prewarm_game() -> void:
	await UIManager.warm_pool_async(UiName.GAME)
	LevelSelector.prewarm_strategy()
	var lv: int = GameState.get_current_level()
	var sz: int = SizeModifier.get_size(lv)
	var game: Node = UIManager.get_ui(UiName.GAME)
	if game != null and game.has_method("prewarm_board") and sz > 0:
		await game.prewarm_board(sz)
	if sz > 0:
		BankData.get_ranks(sz)
		BankData.get_lk_style_ranks(sz)
		BankData.get_gc_ranks(sz)

		if ABTestManager.normal_level.get_pace_group() > 0 or not OS.has_feature("rel"):
			BankData.prewarm_pace(sz)


## 回到前台且启动已完成：补一次快捷方式检查（启动那会儿可能还没收到）
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _startup_complete:
		_try_handle_shortcut.call_deferred()


## 运行中收到快捷方式：启动没走完就先记着，走完再处理
func _on_shortcut_received_pushed(_type: String) -> void:
	if not _startup_complete:
		return
	_try_handle_shortcut.call_deferred()


const _STREAK_PUSH_ID: String = "streak_broken"


## 读取原生推送启动参数，识别断签召回后给 HomePage 留待处理标记。
func _read_streak_push_click() -> void:
	var payload_json: String = NativeUtilManager.get_launch_push_extras()
	print(
		(
			"[StreakPush] read (cold start, pre-route) payload_len=%d payload=[%s]"
			% [payload_json.length(), payload_json]
		)
	)
	if payload_json.is_empty():
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	if parsed is not Dictionary:
		print("[StreakPush] click payload 解析失败: %s" % payload_json)
		return
	var payload: Dictionary = parsed
	var is_streak_push: bool = String(payload.get("event_id", "")) == _STREAK_PUSH_ID
	if not is_streak_push:
		is_streak_push = payload_json.find(_STREAK_PUSH_ID) >= 0
	if not is_streak_push:
		print("[StreakPush] click 非断签召回 push,忽略: %s" % payload_json)
		return
	print("[StreakPush] click 命中断签召回 push → 置 home 待处理枚举(on_show flush 前判定)")
	HomePage.pending_push_click = HomePage.StreakPushPending.COLD_START_CLICK


## 会话改变且冷启动已完成时，通知排行榜活动并延迟尝试打开活动页。
func _on_session_changed(new_session_id: String) -> void:
	print("[Launcher] SessionId change to %s" % new_session_id)
	if not _startup_complete:
		return

	if RankActivityManager.notify_new_session():
		_open_rank_for_new_session.call_deferred()


## 只在主页或胜利页显示期间承接新会话的排行榜入口。
func _open_rank_for_new_session() -> void:
	var home: HomePage = UIManager.get_ui(UiName.HOME) as HomePage
	if home != null and home.is_showing():
		home.try_open_rank_for_new_session()
		return
	var win: UIFrameWindow = UIManager.get_ui(UiName.WIN)
	if win != null and win.is_showing():
		RankActivityManager.maybe_open(false)


## 处理快捷方式入口；返回 true 表示已经跳转，调用方不用再走正常落地
func _try_handle_shortcut() -> bool:
	# 当前待处理的快捷方式 key，空串表示没有
	var shortcut_key: String = ShortcutManager.get_shortcut_key()
	# 反馈入口：清 key、按「移除桌面图标启动」口径埋点，然后打开反馈页
	if shortcut_key == ShortcutManager.FEEDBACK_ACTION_ID:
		ShortcutManager.clear_shortcut_key()
		Tracker.track_remove_app_start()
		_open_feedback_from_shortcut()
		return true
	# 重要提示入口：只清 key 与埋点，不在这里跳转（返回 false 让调用方走正常流程）
	if shortcut_key == ShortcutManager.IMPORTANT_ACTION_ID:
		ShortcutManager.clear_shortcut_key()
		Tracker.track_remove_app_start()
		return false
	return false


## 打开反馈页；等它关闭后补一个落地页，避免停在空白页
func _open_feedback_from_shortcut() -> void:
	# 等反馈页自己关（closed 信号），再收起它
	var page := UIManager.show_ui(UiName.FEEDBACK)
	await page.closed
	UIManager.hide_ui(UiName.FEEDBACK)

	# 已经在游戏里就不打扰，保持当前局面
	var game_node: Node = UIManager.get_ui(UiName.GAME)
	var daily_node: Node = UIManager.get_ui(UiName.DAILY_GAME)
	if (game_node != null and game_node.visible) or (daily_node != null and daily_node.visible):
		return
	# 否则按引导进度补主页或新手引导
	if GameState.is_tutorial_done():
		var home_node: Node = UIManager.get_ui(UiName.HOME)
		if home_node == null or not home_node.visible:
			UIManager.show_ui(UiName.HOME)
	else:
		var tut_node: Node = UIManager.get_ui(UiName.TUTORIAL)
		if tut_node == null or not tut_node.visible:
			UIManager.show_ui(UiName.TUTORIAL)


# ================= 每日推送 =================
## 清掉旧的每日推送注册（中午 / 晚上两条）
func _clear_daily_pushes() -> void:
	print("[xxztest]clear register daily push new pool")
	UniKitManager.remove_push("daily_noon")
	UniKitManager.remove_push("daily_evening")


## 按本地推送文案实验选择传统文案池或颜色文案池。
func _register_daily_pushes() -> void:
	var clr_group: int = ABTestManager.push_local_text.clr_pool_group()
	if clr_group > 0:
		print("[xxztest]register daily push clr pool G%d" % clr_group)
		_register_clr_pushes(clr_group)
	else:
		print("[xxztest]register daily push")
		_register_legacy_pushes()


## 为推送文案补上实验指定的声音，再交 UniKit 注册每日定时推送。
func _add_daily_push_with_sound(push_id: String, hour: float, contents: Array[Dictionary]) -> void:
	var sound_name: String = PushSoundsConfig.sound_name_for(
		ABTestManager.push_sounds.sound_group(), push_id
	)
	if not sound_name.is_empty():
		for c: Dictionary in contents:
			c["sound"] = sound_name
	UniKitManager.add_daily_push(push_id, hour, contents)


## 用传统文案池分别注册当地中午十二点和晚间二十点的推送。
func _register_legacy_pushes() -> void:
	var title: String = tr("PUSH_TITLE")
	var evening_contents: Array[Dictionary] = []
	for i: int in range(5, 9):
		evening_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
	_add_daily_push_with_sound("daily_noon", 12, _legacy_noon_contents())
	_add_daily_push_with_sound("daily_evening", 20, evening_contents)


## 组装四条传统午间推送文案，翻译由当前语言决定。
func _legacy_noon_contents() -> Array[Dictionary]:
	var title: String = tr("PUSH_TITLE")
	var contents: Array[Dictionary] = []
	for i: int in range(1, 5):
		contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
	return contents


## 构建并打乱实验组晚间文案池，取五条注册；午间继续使用传统文案。
func _register_clr_pushes(group: int) -> void:
	const BG_COLOR: String = "#00F4F4F4"
	var evening_all: Array[Dictionary] = []
	for i: int in range(1, 40):
		(
			evening_all
			. append(
				{
					"title": tr("PUSH2_CLR_G%d_EVE_TITLE_%d" % [group, i]),
					"content": tr("PUSH2_CLR_G%d_EVE_BODY_%d" % [group, i]),
					"bg_color": BG_COLOR,
				}
			)
		)
	evening_all.shuffle()
	_add_daily_push_with_sound("daily_noon", 12, _legacy_noon_contents())
	_add_daily_push_with_sound("daily_evening", 20, evening_all.slice(0, 5))


## 读取平台配置、首次打开时间和订阅商品构造 UniKit 参数，初始化后注册推送命令回调。
func _initialize_unikit_sdk() -> void:
	var params := UniKitInitParams.new()
	params.first_open_time_ms = GameState.get_first_open_time_ms()

	params.is_debug = OS.is_debug_build()

	params.is_show_log = OS.is_debug_build() or OS.has_feature("pre")

	params.is_auto_finish_transaction_enabled = true

	params.is_late_init_purchase = false

	params.subscription_product_ids = PackedStringArray(PurchaseManager.get_sub_product_ids_cfg())
	var cfg: Resource = load("res://unikit_config.tres")
	if cfg != null:
		if OS.has_feature("ios") and cfg.ios != null:
			params.production_id = cfg.ios.production_id
			params.app_store_id = cfg.ios.app_store_id
			params.app_store_url = cfg.ios.app_store_url
		elif OS.has_feature("android") and cfg.android != null:
			params.production_id = cfg.android.production_id
	UniKit.initialize(params)

	UniKit.push_module.register_cmd_callback()


## 按平台调用原生闪屏隐藏接口，淡出时长以毫秒为单位。
func _hide_native_splash(fade_ms: int) -> void:
	if OS.has_feature("ios"):
		NativeUtilManager.hide_native_splash(fade_ms)
	elif OS.has_feature("android"):
		if Engine.has_singleton("SplashPlugin"):
			Engine.get_singleton("SplashPlugin").hideSplash(fade_ms)


# ================= 合规弹窗 / 授权等待 =================
## 把用户 ID 绑给 Crashlytics；非 release 一律用 debug，便于区分
func _bind_crashlytics_user_id() -> void:
	var user_id: String = UniKitManager.get_uuid() if OS.has_feature("rel") else "debug"
	UniKitManager.set_crashlytics_user_id(user_id)


## CMP 回调最多等 2 秒；需要展示 ATT 时继续等其流程完成，再留 1 秒让原生视图退场。
func _wait_cmp_then_att_max_2s() -> void:
	# Android 没有 ATT，CMP 只给个空回调占位
	var emptyCallback: Callable = func() -> void: pass

	# Android：只过 CMP，不等 ATT
	var is_android: bool = OS.has_feature("android")
	if is_android:
		UniKitManager.check_cmp(emptyCallback)
		return

	# iOS：已经问过 ATT（或引导已展示过）就直接跟 CMP 走
	var shown_guide: bool = GameState.has_shown_att_guide()
	var att_status: int = UniKitManager.get_att_status()
	if (
		(shown_guide or att_status != UniKitManager.ATT_STATUS_NOT_DETERMINED)
		and not UniKitManager.debug_force_editor_test
	):
		UniKitManager.check_cmp(AttGuideHelper.try_show_and_wait_dialog_close)
		return

	# CMP 最长等待 2000 毫秒
	const CMP_MAX_WAIT_MS: int = 2000

	# 用字典在异步回调之间传状态：cmp_done / att_needed / att_flow_done
	var state: Dictionary = {"cmp_done": false, "att_needed": false, "att_flow_done": false}
	# CMP 回调里：先标记 CMP 完成；能弹 ATT 才弹，弹完再标记 att_flow_done
	UniKitManager.check_cmp(
		func() -> void:
			state.cmp_done = true
			if not UniKitManager.can_show_att():
				return
			state.att_needed = true
			await AttGuideHelper.try_show_and_wait_dialog_close()
			state.att_flow_done = true
	)

	# 轮询等 CMP 完成，超时就直接返回
	var t0: int = Time.get_ticks_msec()
	while not state.cmp_done and Time.get_ticks_msec() - t0 < CMP_MAX_WAIT_MS:
		await get_tree().process_frame
	if not state.cmp_done:
		return
	# CMP 说不用弹 ATT 就结束
	if not state.att_needed:
		return

	# 等 ATT 弹窗真正关掉
	while not state.att_flow_done:
		await get_tree().process_frame

	# 再留 1 秒缓冲，让 CMP / ATT 的原生视图完全退场
	await get_tree().create_timer(1.0).timeout


# ================= 闪屏收尾 =================
## 等闪屏播完：入页不足 2 秒也至少补到 2 秒，再多留 0.5 秒，避免一闪而过
func _wait_splash_complete() -> void:
	# 闪屏实例没了（被提前收掉）就不用等
	if _splash_page == null or not is_instance_valid(_splash_page):
		return
	# 已展示时长不足 2 秒就补到 2 秒，然后统一多留 0.5 秒
	var elapsed_ms: int = Time.get_ticks_msec() - _perf_t0
	var wait_sec: float
	if elapsed_ms >= 2000:
		wait_sec = 0.5
	else:
		wait_sec = (2000 - elapsed_ms) / 1000.0 + 0.5
	await get_tree().create_timer(wait_sec).timeout
	# 让闪屏立刻走完（可能还有没播完的动画）
	if not is_instance_valid(_splash_page):
		return
	_splash_page.force_complete()
	# 等闪屏自己的 loading_complete 信号
	await _splash_page.loading_complete
