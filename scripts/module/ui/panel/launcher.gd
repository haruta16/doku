# 启动器：主场景 launcher.tscn 的根脚本，掌管冷启动全过程
# 顺序：日志/性能埋点 → 语言 → 作弊面板（非 release）→ 闪屏 → 隐私与推送 → AB 就绪 → 预热 → 进主页或引导
extends Node

# ---- 预加载资源 ----
const _CHEAT_COMMANDS: GDScript = preload("res://scripts/module/ui/panel/cheat_commands.gd") # 作弊命令集：非 release 才实例化
const _CHEAT_OVERLAY: PackedScene = preload("res://addons/cheat_manager/cheat_overlay.tscn") # 作弊面板覆盖层场景

const _SPLASH_SCENE: PackedScene = preload("res://scripts/module/splash/ui/splash_page.tscn") # 闪屏页场景：提前 preload；实际显示走 UIManager 的注册表，这里目前只是一份冗余引用

# ---- 启动期运行时状态 ----
var _splash_page = null # 闪屏页实例（由 UIManager 创建），收尾时对它 force_complete
var _startup_complete: bool = false # 冷启动是否走完；走完才允许响应快捷方式与前台事件

var _crashlytics_logger: LogUtil = null # 把 Godot 日志转发给 Crashlytics 的 Logger

var _in_game_log_buffer: InGameLogBuffer = null # 内存日志缓冲，作弊面板「日志」页的数据源

# ---- 启动性能埋点（毫秒时间戳） ----
var _perf_t0: int = 0 # 启动开始时刻
var _perf_last: int = 0 # 上一步的时刻，用来算单步耗时
var _perf_emitted: Dictionary = {} # 已上报的 step 去重表


# ================= 启动性能埋点 =================
# 上报一个启动阶段耗时；同一步只上报一次，重复调用直接忽略
func _emit_perf(step: String) -> void:
    # 已报过就不再发，避免超时兜底与事件竞态导致重复埋点
    if _perf_emitted.has(step):
        return
    _perf_emitted[step] = true
    # cost＝距上一步，total＝距启动开始
    var now: int = Time.get_ticks_msec()
    Tracker.track_perf_monitor("app_start", step, now - _perf_last, now - _perf_t0)
    _perf_last = now


# ================= 冷启动主流程 =================
# 冷启动总流程：一路 await 到闪屏播完，最后决定进主页还是新手引导
func _ready() -> void:
    # 日志先接上：之后的报错都会进 Crashlytics
    _crashlytics_logger = LogUtil.new()
    OS.add_logger(_crashlytics_logger)
    # 同时挂一份内存日志，作弊面板「日志」页读的就是它
    _in_game_log_buffer = InGameLogBuffer.new()
    InGameLogBuffer.instance = _in_game_log_buffer
    OS.add_logger(_in_game_log_buffer)

    # 锁 60 帧：移动端省电，动画节奏也稳
    Engine.max_fps = 60

    # 游戏期间不让屏幕自动熄灭
    DisplayServer.screen_set_keep_on(true)

    # 记录启动计时原点
    _perf_t0 = Time.get_ticks_msec()
    _perf_last = _perf_t0

    # 首次启动跟随系统语言
    LanguageManager.apply_system_locale()

    # 会话变化只打日志，便于排查跨天/前后台问题
    SessionManager.session_changed.connect(_on_session_changed)

    # 首启持久化落盘（安装天数、生命周期分段都要用）
    GameState.consume_first_session_persist()

    # 非 release 构建才挂作弊命令集与作弊面板
    if not OS.has_feature("rel"):
        add_child(_CHEAT_COMMANDS.new())
        add_child(_CHEAT_OVERLAY.instantiate())

    # Android 上先等 1 秒：给原生闪屏留时间，避免中间露出黑屏
    if OS.has_feature("android"):
        await get_tree().create_timer(1.0).timeout

    # 显示游戏内闪屏页；后面的初始化都在它背后进行
    _splash_page = UIManager.show_ui(UiName.SPLASH)

    # 通知原生层隐藏启动闪屏（淡出 500 毫秒）
    _hide_native_splash(500)

    # 闪屏已就绪，上报第一个性能节点
    _emit_perf(Tracker.PerfStep.LOAD_SPLASH)

    # 统计/归因 SDK（Tracker 里这一步叫 INIT_GAME_MANAGER）：已就绪就直接上报，否则等一次性完成信号
    if UniKitManager.is_analyze_inited():
        _emit_perf(Tracker.PerfStep.INIT_GAME_MANAGER)
    else:
        UniKitManager.analyze_init_completed.connect(
            _emit_perf.bind(Tracker.PerfStep.INIT_GAME_MANAGER), CONNECT_ONE_SHOT
        )
    # 广告管理器同上
    if UniKitManager.is_ad_inited():
        _emit_perf(Tracker.PerfStep.INIT_AD_MANAGER)
    else:
        UniKitManager.ad_init_completed.connect(
            _emit_perf.bind(Tracker.PerfStep.INIT_AD_MANAGER), CONNECT_ONE_SHOT
        )

    # 分析 SDK 就绪后，把崩溃上报的用户 ID 绑上
    if UniKitManager.is_analyze_inited():
        _bind_crashlytics_user_id()
    else:
        UniKitManager.analyze_init_completed.connect(_bind_crashlytics_user_id, CONNECT_ONE_SHOT)

    # 注册桌面快捷方式入口（反馈 / 重要提示）
    ShortcutManager.add_shortcuts(tr("SHORTCUT_FEEDBACK_TITLE"), tr("SHORTCUT_IMPORTANT_TITLE"))

    # 从快捷方式冷启动时，等启动完成再处理跳转
    ShortcutManager.connect_shortcut_received(_on_shortcut_received_pushed)

    # 需要同意隐私政策：等用户点同意后再初始化需要授权的 SDK
    if UniKitManager.check_privacy_required():
        var privacy_dialog: Node = UIManager.show_ui(UiName.PRIVACY)
        await privacy_dialog.accepted
        UIManager.hide_ui(UiName.PRIVACY)
        UniKitManager.agree_privacy()

    # 初始化 ATT（iOS 广告追踪授权）
    UniKitManager.init_att()

    # 推送权限最多问 2 次，避免反复骚扰
    if (OS.has_feature("android") or OS.has_feature("ios")) and GameState.get_push_ask_count() < 2:
        UniKitManager.request_push_permission()
        await UniKitManager.push_permission_done
        GameState.inc_push_ask_count()

    # 先清掉旧的每日推送，等 0.5 秒让清理生效，再按 AB 分组重新注册
    UniKitManager.set_push_enabled(true)
    _clear_daily_pushes()
    await get_tree().create_timer(0.5).timeout
    _register_daily_pushes()

    # 让出一帧：把上面的异步清理排到本帧之后再继续
    await get_tree().process_frame

    # CMP（同意管理平台）与 ATT 弹窗最多等 2 秒，不阻塞启动
    await _wait_cmp_then_att_max_2s()

    # AB 远端配置最多等 2 秒
    await ABTestManager.await_remote_ready(2.0)

    # 屏幕适配初始化
    ScreenManager.setup()

    # 预热对局页：提前加载场景与题库，缩短首次进关的等待
    _prewarm_game()

    # AB 配置里的默认音乐开关（等配置到齐再定）
    _init_music_default_when_ab_loaded()

    # 等闪屏播完
    await _wait_splash_complete()

    # 启动流程结束，上报最后一个性能节点
    _emit_perf(Tracker.PerfStep.END)

    # 落地优先级：快捷方式跳转 > 教程没走完进教程 > 否则进主页
    if _try_handle_shortcut():
        pass
    elif GameState.is_tutorial_done():
        UIManager.show_ui(UiName.HOME)
    else:
        UIManager.show_ui(UiName.TUTORIAL)

    # 收掉闪屏；此后前台事件与快捷方式才开始生效
    UIManager.hide_ui(UiName.SPLASH)
    _startup_complete = true


# 等 AB 配置里的音乐默认值就绪（最多 8 秒），再写进存档
func _init_music_default_when_ab_loaded() -> void:
    var cfg: BgmTestConfig = ABTestManager.bgm_test
    # 配置没到就轮询等；超时直接放弃，宁可不写也不写错值
    if not cfg.is_value_loaded():
        var timer: SceneTreeTimer = get_tree().create_timer(8.0)
        while not cfg.is_value_loaded() and timer.time_left > 0.0:
            await get_tree().process_frame
        if not cfg.is_value_loaded():
            return
    GameState.init_music_default(cfg.default_music_on())


# 预热对局页：后台加载场景、按当前关卡尺寸喂棋盘、顺手把题库排名预计算好
func _prewarm_game() -> void:
    # 异步加载并实例化对局页（保持隐藏）
    await UIManager.warm_pool_async(UiName.GAME)
    # 当前关卡尺寸；AB 实验组走 size_group_j 的另一套尺寸
    var lv: int = GameState.get_current_level()
    var sz: int = (
        LevelData.get_size_group_j(lv)
        if ABTestManager.rule_normal_rank.is_group_j()
        else LevelData.get_size(lv)
    )
    # 让对局页先按尺寸把棋盘建出来，首次进关能少等一截
    var game: Node = UIManager.get_ui(UiName.GAME)
    if game != null and game.has_method("prewarm_board") and sz > 0:
        await game.prewarm_board(sz)
    # 题库的三张排名表按尺寸预计算（题库页首屏要用）
    if sz > 0:
        BankData.get_ranks(sz)
        BankData.get_lk_style_ranks(sz)
        BankData.get_gc_ranks(sz)


# 回到前台且启动已完成：补一次快捷方式检查（启动那会儿可能还没收到）
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN and _startup_complete:
        _try_handle_shortcut.call_deferred()


# 运行中收到快捷方式：启动没走完就先记着，走完再处理
func _on_shortcut_received_pushed(_type: String) -> void:
    if not _startup_complete:
        return
    _try_handle_shortcut.call_deferred()


# 会话 ID 变化只打日志
func _on_session_changed(new_session_id: String) -> void:
    print("[Launcher] SessionId change to %s" % new_session_id)


# 处理快捷方式入口；返回 true 表示已经跳转，调用方不用再走正常落地
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


# 打开反馈页；等它关闭后补一个落地页，避免停在空白页
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
# 清掉旧的每日推送注册（中午 / 晚上两条）
func _clear_daily_pushes() -> void:
    print("[xxztest]clear register daily push new pool")
    UniKitManager.remove_push("daily_noon")
    UniKitManager.remove_push("daily_evening")


# 按 AB 分组注册每日推送：新文案池从 100 条里抽 5 条，老池走固定文案
func _register_daily_pushes() -> void:
    if ABTestManager.push_local_text.is_new_pool():
        print("[xxztest]register daily push new pool")
        _register_new_pushes()
    else:
        print("[xxztest]register daily push")
        _register_legacy_pushes()


# 老文案池：中午 12 点、晚上 20 点各推一条，文案 4 选 1
func _register_legacy_pushes() -> void:
    # 标题所有推送共用
    var title: String = tr("PUSH_TITLE")
    var noon_contents: Array[Dictionary] = []
    # 中午用 PUSH_CONTENT_1~4
    for i: int in range(1, 5):
        noon_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
    var evening_contents: Array[Dictionary] = []
    # 晚上用 PUSH_CONTENT_5~8
    for i: int in range(5, 9):
        evening_contents.append({"title": title, "content": tr("PUSH_CONTENT_%d" % i)})
    UniKitManager.add_daily_push("daily_noon", 12, noon_contents)
    UniKitManager.add_daily_push("daily_evening", 20, evening_contents)


# 新文案池：各 100 条文案先打乱再取前 5 条，避免每次都是同样几条
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


# ================= 平台桥接 =================
# 通知原生层隐藏启动闪屏（iOS 走 UniKitPlugin，Android 走 SplashPlugin）
func _hide_native_splash(fade_ms: int) -> void:
    if OS.has_feature("ios"):
        if Engine.has_singleton("UniKitPlugin"):
            Engine.get_singleton("UniKitPlugin").hideSplash(fade_ms)
    elif OS.has_feature("android"):
        if Engine.has_singleton("SplashPlugin"):
            Engine.get_singleton("SplashPlugin").hideSplash(fade_ms)


# ================= 合规弹窗 / 授权等待 =================
# 把用户 ID 绑给 Crashlytics；非 release 一律用 debug，便于区分
func _bind_crashlytics_user_id() -> void:
    var user_id: String = UniKitManager.get_uuid() if OS.has_feature("rel") else "debug"
    UniKitManager.set_crashlytics_user_id(user_id)


# 等 CMP 同意弹窗与 ATT 授权走完，最长 2 秒；超时就继续启动，不卡用户
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
# 等闪屏播完：入页不足 2 秒也至少补到 2 秒，再多留 0.5 秒，避免一闪而过
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
