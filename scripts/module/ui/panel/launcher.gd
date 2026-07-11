extends Node

const _CHEAT_COMMANDS: GDScript = preload("res://scripts/module/ui/panel/cheat_commands.gd")
const _CHEAT_OVERLAY: PackedScene = preload("res://addons/cheat_manager/cheat_overlay.tscn")

const _SPLASH_SCENE: PackedScene = preload("res://scripts/module/splash/ui/splash_page.tscn")

var _splash_page = null
var _startup_complete: bool = false

var _crashlytics_logger: LogUtil = null

var _in_game_log_buffer: InGameLogBuffer = null

var _perf_t0: int = 0
var _perf_last: int = 0
var _perf_emitted: Dictionary = {}


func _emit_perf(step: String) -> void:
    if _perf_emitted.has(step):
        return
    _perf_emitted[step] = true
    var now: int = Time.get_ticks_msec()
    Tracker.track_perf_monitor("app_start", step, now - _perf_last, now - _perf_t0)
    _perf_last = now


func _ready() -> void:
    _crashlytics_logger = LogUtil.new()
    OS.add_logger(_crashlytics_logger)
    _in_game_log_buffer = InGameLogBuffer.new()
    InGameLogBuffer.instance = _in_game_log_buffer
    OS.add_logger(_in_game_log_buffer)

    Engine.max_fps = 60

    DisplayServer.screen_set_keep_on(true)

    _perf_t0 = Time.get_ticks_msec()
    _perf_last = _perf_t0

    LanguageManager.apply_system_locale()

    SessionManager.session_changed.connect(_on_session_changed)

    GameState.consume_first_session_persist()

    if not OS.has_feature("rel"):
        add_child(_CHEAT_COMMANDS.new())
        add_child(_CHEAT_OVERLAY.instantiate())

    if OS.has_feature("android"):
        await get_tree().create_timer(1.0).timeout

    _splash_page = UIManager.show_ui(UiName.SPLASH)

    _hide_native_splash(500)

    _emit_perf(Tracker.PerfStep.LOAD_SPLASH)

    if UniKitManager.is_analyze_inited():
        _emit_perf(Tracker.PerfStep.INIT_GAME_MANAGER)
    else:
        UniKitManager.analyze_init_completed.connect(
            _emit_perf.bind(Tracker.PerfStep.INIT_GAME_MANAGER), CONNECT_ONE_SHOT
        )
    if UniKitManager.is_ad_inited():
        _emit_perf(Tracker.PerfStep.INIT_AD_MANAGER)
    else:
        UniKitManager.ad_init_completed.connect(
            _emit_perf.bind(Tracker.PerfStep.INIT_AD_MANAGER), CONNECT_ONE_SHOT
        )

    if UniKitManager.is_analyze_inited():
        _bind_crashlytics_user_id()
    else:
        UniKitManager.analyze_init_completed.connect(_bind_crashlytics_user_id, CONNECT_ONE_SHOT)

    ShortcutManager.add_shortcuts(tr("SHORTCUT_FEEDBACK_TITLE"), tr("SHORTCUT_IMPORTANT_TITLE"))

    ShortcutManager.connect_shortcut_received(_on_shortcut_received_pushed)

    if UniKitManager.check_privacy_required():
        var privacy_dialog: Node = UIManager.show_ui(UiName.PRIVACY)
        await privacy_dialog.accepted
        UIManager.hide_ui(UiName.PRIVACY)
        UniKitManager.agree_privacy()

    UniKitManager.init_att()

    if (OS.has_feature("android") or OS.has_feature("ios")) and GameState.get_push_ask_count() < 2:
        UniKitManager.request_push_permission()
        await UniKitManager.push_permission_done
        GameState.inc_push_ask_count()

    UniKitManager.set_push_enabled(true)
    _clear_daily_pushes()
    await get_tree().create_timer(0.5).timeout
    _register_daily_pushes()

    await get_tree().process_frame

    await _wait_cmp_then_att_max_2s()

    await ABTestManager.await_remote_ready(2.0)

    ScreenManager.setup()

    _prewarm_game()

    _init_music_default_when_ab_loaded()

    await _wait_splash_complete()

    _emit_perf(Tracker.PerfStep.END)

    if _try_handle_shortcut():
        pass
    elif GameState.is_tutorial_done():
        UIManager.show_ui(UiName.HOME)
    else:
        UIManager.show_ui(UiName.TUTORIAL)

    UIManager.hide_ui(UiName.SPLASH)
    _startup_complete = true


func _init_music_default_when_ab_loaded() -> void:
    var cfg: BgmTestConfig = ABTestManager.bgm_test
    if not cfg.is_value_loaded():
        var timer: SceneTreeTimer = get_tree().create_timer(8.0)
        while not cfg.is_value_loaded() and timer.time_left > 0.0:
            await get_tree().process_frame
        if not cfg.is_value_loaded():
            return
    GameState.init_music_default(cfg.default_music_on())


func _prewarm_game() -> void:
    await UIManager.warm_pool_async(UiName.GAME)
    var lv: int = GameState.get_current_level()
    var sz: int = (
        LevelData.get_size_group_j(lv)
        if ABTestManager.rule_normal_rank.is_group_j()
        else LevelData.get_size(lv)
    )
    var game: Node = UIManager.get_ui(UiName.GAME)
    if game != null and game.has_method("prewarm_board") and sz > 0:
        await game.prewarm_board(sz)
    if sz > 0:
        BankData.get_ranks(sz)
        BankData.get_lk_style_ranks(sz)
        BankData.get_gc_ranks(sz)


func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN and _startup_complete:
        _try_handle_shortcut.call_deferred()


func _on_shortcut_received_pushed(_type: String) -> void:
    if not _startup_complete:
        return
    _try_handle_shortcut.call_deferred()


func _on_session_changed(new_session_id: String) -> void:
    print("[Launcher] SessionId change to %s" % new_session_id)


func _try_handle_shortcut() -> bool:
    var shortcut_key: String = ShortcutManager.get_shortcut_key()
    if shortcut_key == ShortcutManager.FEEDBACK_ACTION_ID:
        ShortcutManager.clear_shortcut_key()
        Tracker.track_remove_app_start()
        _open_feedback_from_shortcut()
        return true
    if shortcut_key == ShortcutManager.IMPORTANT_ACTION_ID:
        ShortcutManager.clear_shortcut_key()
        Tracker.track_remove_app_start()
        return false
    return false


func _open_feedback_from_shortcut() -> void:
    var page := UIManager.show_ui(UiName.FEEDBACK)
    await page.closed
    UIManager.hide_ui(UiName.FEEDBACK)

    var game_node: Node = UIManager.get_ui(UiName.GAME)
    var daily_node: Node = UIManager.get_ui(UiName.DAILY_GAME)
    if (game_node != null and game_node.visible) or (daily_node != null and daily_node.visible):
        return
    if GameState.is_tutorial_done():
        var home_node: Node = UIManager.get_ui(UiName.HOME)
        if home_node == null or not home_node.visible:
            UIManager.show_ui(UiName.HOME)
    else:
        var tut_node: Node = UIManager.get_ui(UiName.TUTORIAL)
        if tut_node == null or not tut_node.visible:
            UIManager.show_ui(UiName.TUTORIAL)


func _clear_daily_pushes() -> void:
    print("[xxztest]clear register daily push new pool")
    UniKitManager.remove_push("daily_noon")
    UniKitManager.remove_push("daily_evening")


func _register_daily_pushes() -> void:
    if ABTestManager.push_local_text.is_new_pool():
        print("[xxztest]register daily push new pool")
        _register_new_pushes()
    else:
        print("[xxztest]register daily push")
        _register_legacy_pushes()


func _register_legacy_pushes() -> void:
    var title: String = tr("PUSH_TITLE")
    var noon_contents: Array[Dictionary] = []
    for i: int in range(1, 5):
        noon_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
    var evening_contents: Array[Dictionary] = []
    for i: int in range(5, 9):
        evening_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
    UniKitManager.add_daily_push("daily_noon", 12, noon_contents)
    UniKitManager.add_daily_push("daily_evening", 20, evening_contents)


func _register_new_pushes() -> void:
    var noon_all: Array[Dictionary] = []
    for i: int in range(1, 101):
        noon_all.append(
            {"title": tr("PUSH_NOON_TITLE_%d" % i), "content": tr("PUSH_NOON_BODY_%d" % i)}
        )
    noon_all.shuffle()
    var evening_all: Array[Dictionary] = []
    for i: int in range(1, 101):
        evening_all.append(
            {"title": tr("PUSH_EVE_TITLE_%d" % i), "content": tr("PUSH_EVE_BODY_%d" % i)}
        )
    evening_all.shuffle()
    UniKitManager.add_daily_push("daily_noon", 12, noon_all.slice(0, 5))
    UniKitManager.add_daily_push("daily_evening", 20, evening_all.slice(0, 5))


func _hide_native_splash(fade_ms: int) -> void:
    if OS.has_feature("ios"):
        if Engine.has_singleton("UniKitPlugin"):
            Engine.get_singleton("UniKitPlugin").hideSplash(fade_ms)
    elif OS.has_feature("android"):
        if Engine.has_singleton("SplashPlugin"):
            Engine.get_singleton("SplashPlugin").hideSplash(fade_ms)


func _bind_crashlytics_user_id() -> void:
    var user_id: String = UniKitManager.get_uuid() if OS.has_feature("rel") else "debug"
    UniKitManager.set_crashlytics_user_id(user_id)


func _wait_cmp_then_att_max_2s() -> void:
    var emptyCallback: Callable = func() -> void: pass

    var is_android: bool = OS.has_feature("android")
    if is_android:
        UniKitManager.check_cmp(emptyCallback)
        return

    var shown_guide: bool = GameState.has_shown_att_guide()
    var att_status: int = UniKitManager.get_att_status()
    if (
        (shown_guide or att_status != UniKitManager.ATT_STATUS_NOT_DETERMINED)
        and not UniKitManager.debug_force_editor_test
    ):
        UniKitManager.check_cmp(AttGuideHelper.try_show_and_wait_dialog_close)
        return

    const CMP_MAX_WAIT_MS: int = 2000

    var state: Dictionary = {"cmp_done": false, "att_needed": false, "att_flow_done": false}
    UniKitManager.check_cmp(
        func() -> void:
            state.cmp_done = true
            if not UniKitManager.can_show_att():
                return
            state.att_needed = true
            await AttGuideHelper.try_show_and_wait_dialog_close()
            state.att_flow_done = true
    )

    var t0: int = Time.get_ticks_msec()
    while not state.cmp_done and Time.get_ticks_msec() - t0 < CMP_MAX_WAIT_MS:
        await get_tree().process_frame
    if not state.cmp_done:
        return
    if not state.att_needed:
        return

    while not state.att_flow_done:
        await get_tree().process_frame

    await get_tree().create_timer(1.0).timeout


func _wait_splash_complete() -> void:
    if _splash_page == null or not is_instance_valid(_splash_page):
        return
    var elapsed_ms: int = Time.get_ticks_msec() - _perf_t0
    var wait_sec: float
    if elapsed_ms >= 2000:
        wait_sec = 0.5
    else:
        wait_sec = (2000 - elapsed_ms) / 1000.0 + 0.5
    await get_tree().create_timer(wait_sec).timeout
    if not is_instance_valid(_splash_page):
        return
    _splash_page.force_complete()
    await _splash_page.loading_complete
