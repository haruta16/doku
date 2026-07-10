class_name GamePage
extends BaseGamePage

enum EntryMode{NORMAL, BANK, BANK_SP, DEBUG_CONFIG, DEBUG_PREBUILT}



@onready var _level_label: Label = $Root / VBoxContainer / Header / LevelLabel
@onready var _level_display_value: Label = $Root / VBoxContainer / Header / LevelDisplay / Value
@onready var _coin_label: Label = $Root / VBoxContainer / Header / CoinLabel
@onready var _prev_btn: Button = $Root / VBoxContainer / Header / PrevBtn
@onready var _next_btn: Button = $Root / VBoxContainer / Header / NextBtn
@onready var _normal_toast: GameNormalToast = $Root / NormalToast
@onready var _hard_toast: GameHardToast = $Root / HardToast


var _active_toast: BaseGameToast = null



@onready var _entry_locked_buttons: Array[Button] = [
    $Root / VBoxContainer / Header / SettingsBtn, 
    $Root / VBoxContainer / Header / GearBtn, 
]


var _entry_btn_lock_seq: int = 0


@onready var _anim_tips: AnimationPlayer = $AnimTips
@onready var _warn_tips: Control = $Root / VBoxContainer / CatHeartRow / Tips
@onready var _warn_bubble: Control = $Root / VBoxContainer / CatHeartRow / Tips / Bubble
@onready var _warn_tail: Sprite2D = $Root / VBoxContainer / CatHeartRow / Tips / Bubble / Tail
@onready var _warn_overlay: ColorRect = $Root / Overlay
@onready var _warn_mask: Sprite2D = $Root / VBoxContainer / CatHeartRow / HeartBg / EtMask007
@onready var _idle_guide_overlay: Control = $Root / IdleGuideOverlay
@onready var _idle_guide_hand: Control = $Root / IdleGuideOverlay / HandHint
@onready var _idle_guide_spine: Node = $Root / IdleGuideOverlay / HandHint / ui_guide_hand
@onready var _idle_guide_msg_panel: Panel = $Root / IdleGuideOverlay / MsgPanel
@onready var _idle_guide_msg_rich: RichTextLabel = $Root / IdleGuideOverlay / MsgPanel / MsgRich
@onready var _idle_mask_layer: Control = $Root / IdleMaskLayer



var _nav_index: int = 0
var _nav_total: int = 0
var _is_hard_level: bool = false
var _revive_count: int = 0
var _restart_count: int = 0
var _coins: int = 40
var _size_cycle: int = 0



var _toast_first_try_hint: bool = false

var _entry_handlers: Dictionary = {}


var _endgame_persist_timer: Timer = null
const ENDGAME_PERSIST_DEBOUNCE_SEC: float = 0.5


var _is_endgame_restore_session: bool = false


const _AUTO_MARK_TUTORIAL_SCENE: PackedScene = preload("res://scripts/module/game/ui/auto_mark_tutorial_overlay.tscn")
var _auto_mark_tutorial_overlay: AutoMarkTutorialOverlay = null

const _AUTO_MARK_TUTORIAL_COL: int = 2


var _idle_guide_shown: bool = false
var _idle_guide_tween: Tween = null
var _idle_mask_tween: Tween = null
var _idle_mask_cell: CellView = null


var _idle_guide_block_buttons: Array[Button] = []
const IDLE_GUIDE_DELAY_SEC: float = 10.0

var _step_trigger_had_cat: bool = false








var _entry_anim_pending_state: Variant = null
var _entry_anim_ad_error_cb: Callable = Callable()
var _entry_anim_ad_closed_cb: Callable = Callable()
var _entry_anim_schedule_ts: int = 0

var _warn_phase: int = 0
var _warn_click_allowed: bool = false


func _set_level_text(text: String, level_num: int = -1) -> void :
    _level_label.text = text
    if _level_display_value != null and level_num >= 0:
        _level_display_value.text = "%d" % level_num

func _set_hard_fire_visible(show: bool) -> void :
    var icon: TextureRect = _level_label.get_node_or_null("HardFireIcon")
    if icon != null:
        icon.visible = show
    if show:
        _level_label.offset_left = -299.0
        _level_label.offset_top = 15.0
        _level_label.offset_right = 361.0
        _level_label.offset_bottom = 95.0
        if icon != null:
            _align_hard_fire_icon.call_deferred()
    else:
        _level_label.offset_left = -336.0
        _level_label.offset_top = 18.0
        _level_label.offset_right = 324.0
        _level_label.offset_bottom = 98.0


func _align_hard_fire_icon() -> void :
    var icon: TextureRect = _level_label.get_node_or_null("HardFireIcon")
    if icon == null or not icon.visible:
        return
    var font: Font = _level_label.get_theme_font("font")
    var font_size: int = _level_label.get_theme_font_size("font_size")
    var text_width: float = font.get_string_size(_level_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
    var label_width: float = _level_label.size.x
    var icon_width: float = 46.0
    var gap: float = 8.0
    icon.offset_right = (label_width - text_width) / 2.0 - gap
    icon.offset_left = icon.offset_right - icon_width


func _ready() -> void :
    _entry_handlers = {
        EntryMode.NORMAL: _setup_entry_normal, 
        EntryMode.BANK: _setup_entry_bank, 
        EntryMode.BANK_SP: _setup_entry_bank_sp, 
        EntryMode.DEBUG_CONFIG: _setup_entry_debug_config, 
        EntryMode.DEBUG_PREBUILT: _setup_entry_debug_prebuilt, 
    }
    _refresh_hearts()
    _board_view.cell_drag_start.connect(_on_board_cell_drag_start)
    _board_view.cell_drag_over.connect(_on_board_cell_drag_over)
    _board_view.cell_drag_end.connect(_on_board_cell_drag_end)

    _board_view.cell_state_changed.connect(_on_board_changed_for_auto_complete)

    _board_view.cell_state_changed.connect(_on_cell_changed_for_auto_mark)

    _board_view.cell_state_changed.connect(_on_cell_changed_for_lock_x)

    _board_view.cell_state_changed.connect(_on_cell_changed_for_step_trigger)
    _hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
    _hint_overlay.layer = 10

    _anim_tips.animation_finished.connect(_on_warn_anim_finished)
    _build_strategy_overlay()

    claim_button_sound($Root / VBoxContainer / Header / SettingsBtn)

    _idle_guide_block_buttons = [
        $Root / VBoxContainer / Header / GearBtn, 
        $Root / VBoxContainer / Header / SettingsBtn, 
    ]
    _endgame_persist_timer = Timer.new()
    _endgame_persist_timer.one_shot = true
    _endgame_persist_timer.wait_time = ENDGAME_PERSIST_DEBOUNCE_SEC
    _endgame_persist_timer.timeout.connect(_flush_endgame_snapshot)
    add_child(_endgame_persist_timer)



func _on_clock_timer_timeout() -> void :
    pass




func _resolve_entry_mode(params: Dictionary) -> EntryMode:
    if params.get("bank_mode", false):
        return EntryMode.BANK_SP if params.get("bank_sp", false) else EntryMode.BANK
    if params.has("debug_config"):
        return EntryMode.DEBUG_CONFIG
    if params.has("debug_prebuilt"):
        return EntryMode.DEBUG_PREBUILT
    return EntryMode.NORMAL


func on_show(params: Dictionary = {}) -> void :



    Tracker.set_active_game_type(Tracker.GameType.NORMAL)



    ABTestManager.dye_at_game_start()
    GameState.set_saved_game_auto_mark(ABTestManager.game_auto_mark.value())
    super.on_show(params)

    _clear_draft_deadlock_state()

    if _active_toast != null:
        _active_toast.hide_toast()

    _is_endgame_restore_session = params.get("endgame_restore", false)




    ABTestManager.dye_at_game_start_normal()

    if ABTestManager.daily_first_level_difficulty.is_enabled():
        GameState.evaluate_daily_first_easy()

    var _dfe_lv: int = params.get("level_index", 0)
    var _dfe_is_normal_entry: bool = (
        _dfe_lv > 0
        and not params.get("bank_mode", false)
        and not params.has("debug_config")
        and not params.has("debug_prebuilt"))
    if _dfe_is_normal_entry and GameState.is_daily_first_easy_available():
        var _dfe_is_hard: bool = (
            LevelData.is_hard_level_group_j(_dfe_lv) if ABTestManager.rule_normal_rank.is_group_j()
            else LevelData.is_hard_level(_dfe_lv))
        if _dfe_is_hard or LevelData.is_special_level(_dfe_lv):

            GameState.consume_daily_first_easy()
            print("[DailyFirstEasy] 特殊/Hard关 level=%d, 不降档, 机会消耗" % _dfe_lv)
        elif _has_user_progress_in_endgame_snapshot(_dfe_lv):

            GameState.consume_daily_first_easy()
            print("[DailyFirstEasy] 有操作残局,残局复原优先,机会消耗 (level=%d)" % _dfe_lv)
        else:

            GameState.clear_endgame_snapshot()
            if not GameState.get_retry_puzzle(_dfe_lv).is_empty():
                GameState.set_retry_puzzle(0, {})
            print("[DailyFirstEasy] 清除缓存,准备取降档新题 (level=%d)" % _dfe_lv)



    if ABTestManager.daily_first_level_difficulty.is_enabled() and not GameState.is_daily_first_easy_available():
        GameState.advance_daily_first_easy_date()


    if _try_consume_endgame_snapshot(params):
        return


    var _entry_lv_for_cached: int = params.get("level_index", 0)
    if (_entry_lv_for_cached > 0
            and not params.get("bank_mode", false)
            and not params.has("debug_config")
            and not params.has("debug_prebuilt")):
        var _cached: Dictionary = GameState.get_retry_puzzle(_entry_lv_for_cached)
        if not _cached.is_empty():
            GameState.clear_current_level_dirty()


            var _cached_params: Dictionary = _cached.duplicate()
            _cached_params["_tracker_status"] = Tracker.GameStatus.CONTINUE
            on_show(_cached_params)
            return


    var _entry_lv_idx: int = params.get("level_index", 0)
    _toast_first_try_hint = (
        _entry_lv_idx > 0
        and not params.get("bank_mode", false)
        and not params.has("debug_config")
        and not params.has("debug_prebuilt")
        and GameState.get_retry_puzzle(_entry_lv_idx).is_empty()
    )
    _size_cycle = ABTestManager.size_cycle.value()

    _board_view.visible = false




    _stat_status = params.get("_tracker_status", Tracker.GameStatus.NEW)
    if _stat_status == Tracker.GameStatus.NEW:
        Tracker.new_game_id(Tracker.GameType.NORMAL)
    _stat_start_ms = Time.get_ticks_msec()

    if not CheatBus.command_issued.is_connected(_on_cheat_command):
        CheatBus.command_issued.connect(_on_cheat_command)


    var _entry_mode: EntryMode = _resolve_entry_mode(params)
    _entry_handlers[_entry_mode].call(params)


    if GameState.is_daily_first_easy_available():
        GameState.consume_daily_first_easy()
        print("[DailyFirstEasy] 兜底消耗 (strategy<=1 或其他路径未消耗)")


    _strategy_btn.visible = not OS.has_feature("rel")

    var _nav_enabled: = _nav_total > 1
    _prev_btn.visible = _nav_enabled
    _next_btn.visible = _nav_enabled
    if _nav_enabled:
        _prev_btn.text = "‹"
        _next_btn.text = "›"


    _lives = 3

    if params.has("restore_lives"):
        _lives = clampi(int(params["restore_lives"]), 0, 3)
        if _lives < 3:
            _ac_had_wrong_cat = true
    _is_complete = false
    _mistake_count = 0
    _revive_count = params.get("restore_revive_count", 0)
    if _stat_status == Tracker.GameStatus.RESTART:
        _restart_count += 1
    elif params.has("restore_restart_count"):
        _restart_count = int(params["restore_restart_count"])
    else:
        _restart_count = 0
    _wrong_guess_pending = false
    _hint_data = {}
    _idle_guide_shown = false
    _step_trigger_had_cat = false
    _stop_idle_guide()
    _last_placed_count = -1


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
    _clock_timer.start()
    UIManager.hide_ui(UiName.FAIL)
    UIManager.hide_ui(UiName.WIN)
    _hint_overlay.visible = false
    if _strategy_overlay != null:
        _strategy_overlay.visible = false

    _reset_life_warning()


    _coin_label.text = str(_coins)
    _refresh_hearts()
    _sync_tools_from_state()


    await get_tree().process_frame


    _relayout_board()

    var sz: int = _level_config["size"]
    _board_view.mouse_filter = Control.MOUSE_FILTER_STOP



    _disconnect_combo_signal()





    var _pat_regions: Array = _level_config.get("patternRegions", [])
    var _board_intro_setup: = $Root as BoardContainerCell_01
    if _board_intro_setup != null:
        _board_intro_setup.set_auto_trigger(false)
    _board_view.setup(sz, _puzzle["regions"], _compute_color_map_for_current(sz), _pat_regions, true)
    if _board_intro_setup != null:
        _board_intro_setup.set_auto_trigger(true)


    _prefill_hints()


    _restore_partial_board()



    if not _level_config.get("restore_state", {}).is_empty():
        complete_auto_mark_for_restore()



    _seed_like_hand_first_cat_from_board()




    _setup_endgame_persist_for_normal_entry(params)
    if _combo_feedback_view == null:
        _combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
    if _combo_feedback_view != null:
        _combo_feedback_view.reset(_combo_score)
        _combo_feedback_view.set_hard(_is_hard_level)
    _connect_combo_signal()


    _update_remaining()




    _entry_anim_playing = true
    _board_view.visible = false
    _board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

    _lock_entry_buttons()

    var board_intro: = $Root as BoardContainerCell_01
    if _anim_player.is_playing():
        _anim_player.stop()

        if board_intro != null and board_intro.animation_finished.is_connected(_on_appear_animation_finished):
            board_intro.animation_finished.disconnect(_on_appear_animation_finished)
    _apply_goal_emphasis_tracks(_level_config.get("level", 0))

    _apply_rule_swipe_collapse(_level_config.get("level", 0))




    _reset_idle_hint()




    if _level_config.get("level", 0) >= 11:
        ABTestManager.dye_at_game_start_normal_11()
    if _level_config.get("level", 0) >= 21:
        ABTestManager.dye_at_game_start_normal_21()


    Tracker.track_game_start(
        _build_qid(), 
        Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)), 
        _stat_status, 
        Tracker.GameType.NORMAL, 
        _get_diffi(), 
        _level_config.get("level", 0), 
        _level_config.get("rank", 0), 
        _level_config.get("size", 0), 
    )








    var ad_pos: String = Tracker.AdPos.NORMAL_START
    if _stat_status == Tracker.GameStatus.RESTART:
        ad_pos = Tracker.AdPos.NORMAL_RESTART
    elif _stat_status == Tracker.GameStatus.CONTINUE:
        ad_pos = Tracker.AdPos.NORMAL_CONTINUE
    var inter_elig: Dictionary = _eval_start_interstitial(params, ad_pos)




    var board_intro_pre: = $Root as BoardContainerCell_01
    if board_intro_pre != null:
        board_intro_pre.set_process(false)
    ($Root / VBoxContainer as Container).queue_sort()
    await get_tree().process_frame
    _schedule_entry_animation_after_interstitial(ad_pos, inter_elig)


    _show_banner_if_eligible("game")



    if _level_config.get("level", 0) >= 21:
        if _draft_btn != null:
            _draft_btn.visible = _is_draft_unlocked()


    _try_restore_draft_marks_from_snapshot()











func _setup_entry_bank(params: Dictionary) -> void :
    var bank_sz: int = params["bank_size"]
    var rank: int = params["bank_rank"]
    var idx: int = params["bank_index"]

    var raw_sol: Array = params.get("prebuilt_solution", [])
    var solution_2d: Array = []
    for r: int in range(bank_sz):
        var row: Array = []
        row.resize(bank_sz)
        row.fill(false)
        if r < raw_sol.size():
            row[int(raw_sol[r])] = true
        solution_2d.append(row)
    var retry_lv: int = params.get("retry_level", 0)
    _level_config = {
        "level": retry_lv, 
        "size": bank_sz, 
        "rank": rank, 
        "seed": params.get("level_seed", 0), 
        "prefill_count": 0, 
        "prefill_positions": params.get("prefill_positions", []), 
        "bank_idx": idx, 
        "bank_params": params.duplicate(), 
        "bank_source": params.get("bank_source", ""), 
        "bank_source_main": params.get("bank_source_main", ""), 
        "bank_tier": params.get("bank_tier", ""), 
        "restore_state": params.get("restore_state", {}), 
        "patternRegions": params.get("patternRegions", params.get("bank_params", {}).get("patternRegions", [])), 
    }

    var raw_regions: Array = params.get("prebuilt_regions", [])
    var int_regions: Array = []
    for row_arr in raw_regions:
        var int_row: Array = []
        for v in row_arr:
            int_row.append(int(v))
        int_regions.append(int_row)
    _puzzle = {
        "regions": int_regions, 
        "solution": solution_2d, 
    }
    if retry_lv > 0:
        _is_hard_level = (LevelData.is_hard_level_group_j(retry_lv)
            if ABTestManager.rule_normal_rank.is_group_j()
            else LevelData.is_hard_level(retry_lv))
        if _is_hard_level:
            _set_level_text(tr("GAME_LEVEL_HARD") % retry_lv, retry_lv)
            _set_hard_fire_visible(true)
        else:
            _set_level_text(tr("GAME_LEVEL_TITLE") % retry_lv, retry_lv)
            _set_hard_fire_visible(false)
    else:
        _is_hard_level = false
        _set_level_text("%d×%d  R%d  #%d" % [bank_sz, bank_sz, rank, idx])
        _set_hard_fire_visible(false)
    _strategy_steps = [
        params.get("r1_steps", 0), params.get("r2_steps", 0), 
        params.get("r3_steps", 0), params.get("r4_steps", 0), 
        params.get("r5_steps", 0), 
    ]
    _nav_index = params.get("bank_index", 1)
    _nav_total = params.get("bank_total", 1)

func _setup_entry_bank_sp(params: Dictionary) -> void :
    var bank_sz: int = params["bank_size"]
    var rank: int = params["bank_rank"]
    var idx: int = params["bank_index"]

    var raw_sol: Array = params.get("prebuilt_solution", [])
    var solution_2d: Array = []
    for r: int in range(bank_sz):
        var row: Array = []
        row.resize(bank_sz)
        row.fill(false)
        if r < raw_sol.size():
            row[int(raw_sol[r])] = true
        solution_2d.append(row)
    var retry_lv: int = params.get("retry_level", 0)
    _level_config = {
        "level": retry_lv, 
        "size": bank_sz, 
        "rank": rank, 
        "seed": params.get("level_seed", 0), 
        "prefill_count": 0, 
        "prefill_positions": params.get("prefill_positions", []), 
        "bank_idx": idx, 
        "bank_params": params.duplicate(), 
        "bank_source": params.get("bank_source", ""), 
        "bank_source_main": params.get("bank_source_main", ""), 
        "bank_tier": params.get("bank_tier", ""), 
        "patternRegions": params.get("patternRegions", params.get("bank_params", {}).get("patternRegions", [])), 
    }

    var raw_regions: Array = params.get("prebuilt_regions", [])
    var int_regions: Array = []
    for row_arr in raw_regions:
        var int_row: Array = []
        for v in row_arr:
            int_row.append(int(v))
        int_regions.append(int_row)
    _puzzle = {
        "regions": int_regions, 
        "solution": solution_2d, 
    }

    var sp_all: Array = BankData.get_sp_levels()
    var pattern: String = "SP"
    if idx - 1 < sp_all.size():
        var sp_entry: Dictionary = sp_all[idx - 1]
        pattern = sp_entry.get("pattern", "SP")
        var raw_prefill: Array = sp_entry.get("prefill_positions", [])
        var int_prefill: Array = []
        for pos in raw_prefill:
            int_prefill.append([int(pos[0]), int(pos[1])])
        _level_config["prefill_positions"] = int_prefill
    _set_level_text("SP  %d×%d  #%d  [%s]" % [bank_sz, bank_sz, idx, pattern])
    _strategy_steps = [
        params.get("r1_steps", 0), params.get("r2_steps", 0), 
        params.get("r3_steps", 0), params.get("r4_steps", 0), 
        params.get("r5_steps", 0), 
    ]
    _nav_index = params.get("bank_index", 1)
    _nav_total = params.get("bank_total", 1)

func _setup_entry_debug_config(params: Dictionary) -> void :
    var dc: Dictionary = params["debug_config"]
    _level_config = dc.duplicate()
    if not _level_config.has("prefill_count"):
        _level_config["prefill_count"] = 0
    if not _level_config.has("prefill_positions"):
        _level_config["prefill_positions"] = []
    const _LGE_PATH: = "res://scripts/editor/queendoku/level_generator_editor.gd"
    var lge: GDScript = load(_LGE_PATH) if ResourceLoader.exists(_LGE_PATH) else null
    if lge == null:
        push_error("[GamePage] debug_config 入口不可用：LevelGeneratorEditor 不在当前包内")
        return
    _puzzle = lge.generate_puzzle(_level_config)
    _set_level_text(dc.get("label", "Debug"))
    _strategy_steps = [0, 0, 0, 0, 0]
    _nav_index = 0
    _nav_total = 0

func _setup_entry_debug_prebuilt(params: Dictionary) -> void :
    var dp: Dictionary = params["debug_prebuilt"]
    var dp_sz: int = dp["size"]
    _level_config = {
        "level": 0, "size": dp_sz, "seed": 0, 
        "prefill_count": 0, "prefill_positions": [], 
    }
    _puzzle = {"regions": dp["regions"], "solution": dp["solution"]}
    _set_level_text(dp.get("label", "Debug"))
    _strategy_steps = [0, 0, 0, 0, 0]
    _nav_index = 0
    _nav_total = 0

func _setup_entry_normal(params: Dictionary) -> void :

    var level_index: int = params.get("level_index", 1)
    level_index = max(1, level_index)
    var lv_entry: Dictionary = LevelData.get_level_entry(level_index, _get_ab_size(level_index))

    var lv_sz: int = int(lv_entry.get("size", 0))
    if lv_sz == 0: lv_sz = _get_ab_size(level_index)
    var lv_rank: int = lv_entry.get("_bank_rank", LevelData.strategy_to_rank(LevelData.get_strategy(level_index)))
    var lv_sol_1d: Array = lv_entry.get("solution", [])
    var lv_sol_2d: Array = []
    for r: int in range(lv_sz):
        var row: Array = []
        row.resize(lv_sz)
        row.fill(false)
        if r < lv_sol_1d.size():
            row[int(lv_sol_1d[r])] = true
        lv_sol_2d.append(row)
    var lv_raw_regions: Array = lv_entry.get("regionMap", [])
    var lv_int_regions: Array = []
    for row_arr: Array in lv_raw_regions:
        var int_row: Array = []
        for v in row_arr:
            int_row.append(int(v))
        lv_int_regions.append(int_row)

    var lv_prefill_pos: Array = LevelData.compute_prefill(level_index, lv_int_regions, lv_sol_1d, lv_sz)
    _level_config = {
        "level": level_index, 
        "size": lv_sz, 
        "rank": lv_rank, 
        "seed": lv_entry.get("seed", 0), 
        "prefill_count": 1 if not lv_prefill_pos.is_empty() else 0, 
        "prefill_positions": [lv_prefill_pos] if not lv_prefill_pos.is_empty() else [], 
        "bank_source": lv_entry.get("_bank_source", "regular"), 
        "bank_source_main": lv_entry.get("_bank_source_main", ""), 
        "bank_idx": lv_entry.get("_bank_idx", 0), 
        "bank_tier": lv_entry.get("_bank_tier", ""), 
        "bank_transform": lv_entry.get("_bank_transform", 0), 
        "custom_color_map": lv_entry.get("colorMap", []), 
        "patternRegions": lv_entry.get("patternRegions", []), 
    }
    var _gs_strategy: int = GameState.get_current_strategy()
    var _gs_rank: int = LevelData.strategy_to_rank(_gs_strategy)
    var _qid: String = "%s_%d" % [lv_entry.get("_bank_source", "regular"), lv_entry.get("_bank_idx", 0)]
    if GameState.is_current_level_daily_first_easy():
        print("[DailyFirstEasy] level=%d 当前难度R%d, 触发首局降档: 实际难度R%d, qid=%s" % [
            level_index, _gs_rank, lv_rank, _qid])
    else:
        print("[DailyFirstEasy] level=%d 当前难度R%d, qid=%s" % [level_index, lv_rank, _qid])

    _strategy_steps[0] = int(lv_entry.get("r1", 0))
    _strategy_steps[1] = int(lv_entry.get("r2", 0))
    _strategy_steps[2] = int(lv_entry.get("r3", 0))
    _strategy_steps[3] = int(lv_entry.get("r4", 0))
    _strategy_steps[4] = int(lv_entry.get("r5", 0))

    if _strategy_steps.all( func(v: int) -> bool: return v == 0):
        var fallback_r: int = int(lv_entry.get("r", lv_entry.get("maxR", 0)))
        if fallback_r >= 1 and fallback_r <= 5:
            _strategy_steps[fallback_r - 1] = int(lv_entry.get("steps", 1))
    _puzzle = {"regions": lv_int_regions, "solution": lv_sol_2d}


    var _pid: String = LevelData.compute_puzzle_id(lv_sz, lv_int_regions)
    var _dup_prev: Dictionary = GameState.record_puzzle(_pid, level_index, UniKitManager.get_version_name(), lv_entry.get("_bank_source_main", lv_entry.get("_bank_source", "")))
    if not _dup_prev.is_empty() and int(_dup_prev.get("level", -1)) != level_index:
        if not params.has("_dedup_retry"):





            LevelData.advance_for_entry(lv_entry, lv_sz)
            var retry_params: Dictionary = params.duplicate()
            retry_params["_dedup_retry"] = true
            _setup_entry_normal(retry_params)
            return
        var _bk: String = "%d_%d" % [lv_sz, lv_rank]
        var _tier_key: String = lv_entry.get("_bank_tier", "")
        var _src: String = lv_entry.get("_bank_source_main", lv_entry.get("_bank_source", ""))

        var _src_main: String = lv_entry.get("_bank_source_main", "")

        var _raw: = func(snap: Dictionary) -> Dictionary:
            return {
                "lkmod": snap.get("lkmod_progress", {}).get(_bk, {}), 
                "main": snap.get("main_bank_progress", {}).get(_bk, {}), 
                "bank": snap.get("bank_progress", {}).get(_bk, null), 
            }
        var _prev_c: Dictionary = {
            "lv": _dup_prev.get("level", -1), 
            "v": _dup_prev.get("v", "?"), 
            "bk": _bk, 
            "src": _dup_prev.get("src", "?"), 
        }
        _prev_c.merge(_raw.call(_dup_prev))
        var _curr_c: Dictionary = {
            "lv": level_index, 
            "v": UniKitManager.get_version_name(), 
            "bk": _bk, 
            "src": _src, 
            "idx": lv_entry.get("_bank_idx", 0), 
            "lkmod": GameState.get_lkmod_progress(lv_sz, lv_rank), 
            "main": GameState.get_main_progress(lv_sz, lv_rank, _tier_key), 
            "bank": GameState.get_bank_progress_snapshot().get(_bk, null), 
        }


        var _is_main: bool = _src_main in ["regular", "lkstyle", "gc"]
        var _has_hist: bool
        if _src_main == "lk_mod":
            _has_hist = not (_prev_c.get("lkmod", {}) as Dictionary).is_empty()
        elif _is_main:
            _has_hist = not (_prev_c.get("main", {}) as Dictionary).is_empty()
        else:
            _has_hist = _prev_c.get("bank") != null
        if not _has_hist:
            LogUtil.error("DUPLICATE_PUZZLE pid=%s | PREV=%s | CURR=%s" % [
                _pid, 
                JSON.stringify(_prev_c), 
                JSON.stringify(_curr_c), 
            ])
        else:
            var _hb: Array = []; var _hlk: Array = []; var _hmi: Array = []; var _hslk: Array = []
            var _prev_track = null
            for _he in GameState.get_recent_puzzles():
                var _he_lk: Dictionary = _he.get("lkmod_progress", {}).get(_bk, {})
                var _he_mp: Dictionary = _he.get("main_bank_progress", {}).get(_bk, {})
                var _he_b = _he.get("bank_progress", {}).get(_bk, null)
                var _track
                if _src_main == "lk_mod":
                    _track = _he_lk.get("idx", null)
                elif _is_main:
                    _track = _he_mp.get("idx", null)
                else:
                    _track = _he_b
                if _track == null or _track == _prev_track:
                    continue
                _prev_track = _track
                _hb.append(_he_b if _he_b != null else -1)
                _hlk.append(_he_lk.get("idx", -1))
                _hmi.append(_he_mp.get("idx", -1))
                _hslk.append(_he_mp.get("since_lk", -1))

            var _compress: = func(arr: Array) -> String:
                if arr.is_empty(): return ""
                var parts: PackedStringArray = []
                var i: int = 0
                while i < arr.size():
                    var j: int = i + 1
                    while j < arr.size() and int(arr[j]) == int(arr[j - 1]) + 1:
                        j += 1
                    if j - i >= 3:
                        parts.append("%d-%d" % [arr[i], arr[j - 1]])
                    else:
                        for k in range(i, j):
                            parts.append(str(arr[k]))
                    i = j
                return ",".join(parts)
            var _hist: Dictionary
            if _src_main == "lk_mod":
                _hist = {"lk": _compress.call(_hlk)}
            elif _is_main:
                _hist = {"mi": _compress.call(_hmi), "slk": _compress.call(_hslk)}
            else:
                _hist = {"b": _compress.call(_hb)}
            LogUtil.error("DUPLICATE_PUZZLE pid=%s | PREV=%s | CURR=%s | HIST=%s" % [
                _pid, 
                JSON.stringify(_prev_c), 
                JSON.stringify(_curr_c), 
                JSON.stringify(_hist), 
            ])
    PuzzleSessionTracker.record(_pid, level_index)
    _is_hard_level = (LevelData.is_hard_level_group_j(level_index)
        if ABTestManager.rule_normal_rank.is_group_j()
        else LevelData.is_hard_level(level_index))
    if _is_hard_level:
        _set_level_text(tr("GAME_LEVEL_HARD") % level_index, level_index)
        _set_hard_fire_visible(true)
    else:
        _set_level_text(tr("GAME_LEVEL_TITLE") % level_index, level_index)
        _set_hard_fire_visible(false)

    GameState.set_retry_puzzle(level_index, {
        "bank_mode": true, 
        "bank_size": lv_sz, 
        "bank_rank": lv_rank, 
        "bank_index": lv_entry.get("_bank_idx", 0), 
        "prebuilt_regions": lv_int_regions, 
        "prebuilt_solution": lv_sol_1d, 
        "level_seed": lv_entry.get("seed", 0), 
        "prefill_positions": [lv_prefill_pos] if not lv_prefill_pos.is_empty() else [], 
        "custom_color_map": lv_entry.get("colorMap", []), 
        "retry_level": level_index, 
        "bank_source": lv_entry.get("_bank_source", "regular"), 
        "bank_source_main": lv_entry.get("_bank_source_main", ""), 
        "bank_tier": lv_entry.get("_bank_tier", ""), 
        "r1_steps": _strategy_steps[0], 
        "r2_steps": _strategy_steps[1], 
        "r3_steps": _strategy_steps[2], 
        "r4_steps": _strategy_steps[3], 
        "r5_steps": _strategy_steps[4], 
    })
    GameState.clear_current_level_dirty()
    _nav_index = level_index
    _nav_total = 0



func on_hide() -> void :
    super.on_hide()

    _clear_draft_deadlock_state()




    _cancel_pending_entry_animation_wait()


    var board_intro: = $Root as BoardContainerCell_01
    if board_intro != null and board_intro.animation_finished.is_connected(_on_appear_animation_finished):
        board_intro.animation_finished.disconnect(_on_appear_animation_finished)
    if _anim_player.is_playing():
        _anim_player.stop()
    if _active_toast != null:
        _active_toast.hide_toast()
    _stop_idle_guide()
    if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
        _board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)

    if _endgame_persist_timer != null and _endgame_persist_timer.time_left > 0.0:
        _endgame_persist_timer.stop()
        _flush_endgame_snapshot()

    _reset_life_warning()

    _free_auto_mark_tutorial_overlay()











func _try_consume_endgame_snapshot(params: Dictionary) -> bool:
    var lv_idx: int = params.get("level_index", 0)
    if (lv_idx <= 0
            or params.get("bank_mode", false)
            or params.has("debug_config")
            or params.has("debug_prebuilt")):
        return false

    if not ABTestManager.normal_endgame_save.is_enabled():
        if not GameState.get_endgame_snapshot().is_empty():
            GameState.clear_endgame_snapshot()
        return false
    var snapshot: Dictionary = GameState.get_endgame_snapshot()
    if snapshot.is_empty():
        return false
    if not _validate_endgame_snapshot(snapshot):
        push_warning("[Endgame] snapshot validation failed, clearing")
        GameState.clear_endgame_snapshot()
        return false
    var snap_level: int = int(snapshot["level"])
    if snap_level != GameState.get_current_level() or snap_level != lv_idx:
        push_warning("[Endgame] snapshot level=%d mismatch (current_level=%d, entry=%d), clearing" %
                [snap_level, GameState.get_current_level(), lv_idx])
        GameState.clear_endgame_snapshot()
        return false
    var lives_left: int = int(snapshot["lives"])
    var sz: int = int(snapshot["size"])
    if lives_left <= 0:
        print("[Endgame] lives==0, clear snapshot and fall through to retry/fresh")
        GameState.clear_endgame_snapshot()
        return false
    var board: Array = _reconstruct_board_for_check(snapshot, sz)
    if QueendokuCore.is_complete(board, sz, snapshot["regionMap"]):
        print("[Endgame] snapshot is_complete, advancing level=%d and re-entering" % snap_level)
        GameState.on_level_won(snap_level)
        GameState.clear_endgame_snapshot()
        var new_params: Dictionary = params.duplicate()
        new_params["level_index"] = GameState.get_current_level()
        new_params["_tracker_status"] = Tracker.GameStatus.NEW
        on_show(new_params)
        return true
    print("[Endgame] restoring in-progress snapshot level=%d lives=%d cats=%d marks=%d errors=%d locked=%d" % [
        snap_level, lives_left, 
        (snapshot.get("placed_cats", []) as Array).size(), 
        (snapshot.get("marks", []) as Array).size(), 
        (snapshot.get("errors", []) as Array).size(), 
        (snapshot.get("locked_marks", []) as Array).size(), 
    ])
    var restore_params: Dictionary = {
        "bank_mode": true, 
        "bank_size": sz, 
        "bank_rank": int(snapshot["r"]), 
        "bank_index": int(snapshot["id"]), 
        "bank_total": 1, 
        "prebuilt_regions": snapshot["regionMap"], 
        "prebuilt_solution": snapshot["solution"], 
        "level_seed": snapshot.get("seed", snapshot["id"]), 
        "prefill_positions": snapshot.get("prefill_positions", []), 
        "bank_source": snapshot.get("bank_source", ""), 
        "bank_source_main": snapshot.get("bank_source_main", ""), 
        "bank_tier": snapshot.get("bank_tier", ""), 
        "retry_level": snap_level, 
        "restore_state": {
            "placed_cats": snapshot.get("placed_cats", []), 
            "marks": snapshot.get("marks", []), 
            "errors": snapshot.get("errors", []), 
            "locked_marks": snapshot.get("locked_marks", []), 
        }, 
        "restore_lives": lives_left, 
        "endgame_restore": true, 
        "restore_step_history": snapshot.get("step_history", []), 
        "restore_combo_count": int(snapshot.get("combo_count", 0)), 
        "restore_combo_score": int(snapshot.get("combo_score", 0)), 
        "restore_restart_count": int(snapshot.get("restart_count", 0)), 
        "restore_revive_count": int(snapshot.get("revive_count", 0)), 
        "restore_life_plus_used": bool(snapshot.get("life_plus_used", false)), 

        "_tracker_status": Tracker.GameStatus.CONTINUE, 
    }
    GameState.clear_current_level_dirty()
    on_show(restore_params)
    return true

func _has_user_progress_in_endgame_snapshot(level: int) -> bool:
    var snapshot: Dictionary = GameState.get_endgame_snapshot()
    if snapshot.is_empty():
        return false
    if int(snapshot.get("level", 0)) != level:
        return false
    if int(snapshot.get("lives", 0)) <= 0:
        return false
    var prefill_count: int = (snapshot.get("prefill_positions", []) as Array).size()
    var user_cats: int = (snapshot.get("placed_cats", []) as Array).size() - prefill_count
    var user_marks: int = (snapshot.get("marks", []) as Array).size()
    var user_errors: int = (snapshot.get("errors", []) as Array).size()

    var user_locked: int = (snapshot.get("locked_marks", []) as Array).size()
    return user_cats > 0 or user_marks > 0 or user_errors > 0 or user_locked > 0



func _validate_endgame_snapshot(snapshot: Dictionary) -> bool:
    if int(snapshot.get("version", 0)) != GameState.ENDGAME_SNAPSHOT_VERSION:
        return false
    var required: Array = [
        "size", "r", "id", "regionMap", "solution", 
        "level", "lives", "placed_cats", "marks", "errors", 
    ]
    for key in required:
        if not snapshot.has(key):
            return false
    var sz: int = int(snapshot["size"])
    if sz <= 0:
        return false
    var rm = snapshot["regionMap"]
    if not (rm is Array) or (rm as Array).size() != sz:
        return false
    for row in (rm as Array):
        if not (row is Array) or (row as Array).size() != sz:
            return false
    var sol = snapshot["solution"]
    if not (sol is Array) or (sol as Array).size() != sz:
        return false
    return true


func _reconstruct_board_for_check(snapshot: Dictionary, sz: int) -> Array:
    var board: Array = []
    for _r: int in range(sz):
        var row: Array = []
        row.resize(sz)
        row.fill(CellState.EMPTY)
        board.append(row)
    for pos in snapshot.get("placed_cats", []):
        var r: int = int(pos[0])
        var c: int = int(pos[1])
        if r >= 0 and r < sz and c >= 0 and c < sz:
            board[r][c] = CellState.CAT
    return board







func _setup_endgame_persist_for_normal_entry(params: Dictionary) -> void :
    if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
        _board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)

    if not ABTestManager.normal_endgame_save.is_enabled():
        return
    var lv_idx: int = params.get("level_index", 0)
    var retry_lv: int = params.get("retry_level", 0)
    var is_normal_mainline: bool = (
        (lv_idx > 0 or retry_lv > 0)
        and not params.has("debug_config")
        and not params.has("debug_prebuilt")
    )
    if is_normal_mainline:
        _board_view.cell_state_changed.connect(_persist_endgame_snapshot)








func _schedule_entry_animation_after_interstitial(ad_position: String, elig: Dictionary) -> void :
    _entry_anim_schedule_ts = Time.get_ticks_msec()

    _cancel_pending_entry_animation_wait()
    if not _try_show_start_interstitial(ad_position, elig):



        var board_intro: = $Root as BoardContainerCell_01
        if board_intro != null:
            board_intro.play()
        _play_entry_animation()
        return



    _anim_player.play(_appear_anim_name())
    _anim_player.seek(0.0, true)
    _anim_player.pause()





    _entry_anim_pending_state = {"done": false}
    _entry_anim_ad_error_cb = func(pid: String, msg: String) -> void :
        if pid != "interstitial":
            return
        _fire_entry_anim("ad_error")
    UniKitManager.ad_error_occurred.connect(_entry_anim_ad_error_cb)



    if OS.has_feature("ios") or OS.has_feature("editor"):
        _entry_anim_ad_closed_cb = func(pid: String) -> void :
            if pid != "interstitial":
                return
            _fire_entry_anim("ad_closed")
        UniKitManager.ad_closed.connect(_entry_anim_ad_closed_cb)







func _fire_entry_anim(source: String) -> void :
    if _entry_anim_pending_state == null:
        return
    if _entry_anim_pending_state.get("done", false):
        return
    _entry_anim_pending_state["done"] = true
    _cancel_pending_entry_animation_wait()




    var board_intro: = $Root as BoardContainerCell_01
    if board_intro != null:
        board_intro.set_process(false)
    ($Root / VBoxContainer as Container).queue_sort()
    await get_tree().process_frame
    if board_intro != null:
        board_intro.play()
    _play_entry_animation()


func _on_application_focus_in() -> void :
    super._on_application_focus_in()
    if _entry_anim_pending_state != null:
        _fire_entry_anim("focus_in")

func _cancel_pending_entry_animation_wait() -> void :

    if _entry_anim_pending_state != null:
        _entry_anim_pending_state["done"] = true
        _entry_anim_pending_state = null
    if not _entry_anim_ad_error_cb.is_null():
        if UniKitManager.ad_error_occurred.is_connected(_entry_anim_ad_error_cb):
            UniKitManager.ad_error_occurred.disconnect(_entry_anim_ad_error_cb)
        _entry_anim_ad_error_cb = Callable()
    if not _entry_anim_ad_closed_cb.is_null():
        if UniKitManager.ad_closed.is_connected(_entry_anim_ad_closed_cb):
            UniKitManager.ad_closed.disconnect(_entry_anim_ad_closed_cb)
        _entry_anim_ad_closed_cb = Callable()

func _play_entry_animation() -> void :
    _board_view.visible = true
    var board_intro: = $Root as BoardContainerCell_01
    _anim_player.play(_appear_anim_name())

    SoundManager.play(SoundManager.Kind.BOARD_ENTER)
    if board_intro != null:




        if not board_intro.animation_finished.is_connected(_on_appear_animation_finished):
            board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)






func _on_appear_animation_finished() -> void :


    var will_show_onboarding: bool = _should_show_draft_onboarding_now()
    super._on_appear_animation_finished()
    if will_show_onboarding and _board_view != null:
        _board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _try_show_start_toast()

    _unlock_entry_buttons_after_toast(_entry_btn_lock_seq)
    if will_show_onboarding:
        _try_show_draft_onboarding_after_appear()

    _auto_mark_prefill_cats()

    _maybe_show_auto_mark_tutorial()



func _process(delta: float) -> void :
    super._process(delta)
    if _idle_guide_shown or _level_config.get("level", 0) != 1 or _entry_anim_playing:
        return

    if ABTestManager.idle_guide.is_idle_guide_enabled():
        if not _is_endgame_restore_session and _can_show_idle_hint():
            if _idle_time >= IDLE_GUIDE_DELAY_SEC:
                _show_idle_guide()

    elif ABTestManager.idle_guide.is_step_trigger_enabled():

        if not _step_trigger_had_cat:
            var sz: int = _level_config.get("size", 0)
            var prefill: Array = _level_config.get("prefill_positions", [])
            var prefill_set: Dictionary = {}
            for pos: Variant in prefill:
                prefill_set[Vector2i(int((pos as Array)[0]), int((pos as Array)[1]))] = true
            if sz > 0:
                for r: int in range(sz):
                    for c: int in range(sz):
                        var st: int = _board_view.get_cell_state(r, c)
                        if st == CellState.CAT\
and not prefill_set.has(Vector2i(r, c)):
                            _step_trigger_had_cat = true
                            break
                    if _step_trigger_had_cat:
                        break



        var _in_double_tap_window: bool = (_gesture_recognizer != null
                and _gesture_recognizer._last_tap_cell != Vector2i(-1, -1))

        var step_trigger_can_show: bool = (visible and not _is_complete
                and not _wrong_guess_pending and not _hint_overlay.visible and _lives > 0)
        if _step_history.size() >= 3 and not _in_double_tap_window\
and not _step_trigger_had_cat and step_trigger_can_show:
            _show_idle_guide()


func _on_cell_changed_for_step_trigger(r: int, c: int, state: int, source: int) -> void :
    if _step_trigger_had_cat:
        return
    if source == BoardView.ChangeSource.RESTORE or source == BoardView.ChangeSource.PREFILL:
        return
    if state != CellState.CAT:
        return
    var prefill: Array = _level_config.get("prefill_positions", [])
    for pos: Variant in prefill:
        if int((pos as Array)[0]) == r and int((pos as Array)[1]) == c:
            return
    _step_trigger_had_cat = true

func _show_idle_guide() -> void :
    if not _hint_mutex.try_acquire("idle_guide"):
        _idle_time = 0.0
        return
    _idle_guide_shown = true

    var regions: Array = _puzzle.get("regions", [])
    var sz: int = _level_config.get("size", 0)
    if sz == 0 or regions.is_empty():
        return
    var area_count: Dictionary = {}
    for r: int in range(sz):
        for c: int in range(sz):
            var rid: int = regions[r][c]
            area_count[rid] = area_count.get(rid, 0) + 1
    var target: Vector2i = Vector2i(-1, -1)
    for r: int in range(sz):
        if target.x >= 0:
            break
        for c: int in range(sz):
            var rid: int = regions[r][c]
            if area_count.get(rid, 0) == 1:
                target = Vector2i(r, c)
                break
    if target.x < 0:
        return

    const BASE_ROW: int = 0
    const BASE_COL: int = 2
    const BASE_OFFSET_LEFT: float = 111.0
    const BASE_OFFSET_TOP: float = -316.0
    var board_scale: float = _board_view.scale.x
    var slot_screen: float = BoardView.SLOT_PX * board_scale
    _idle_guide_hand.offset_left = BASE_OFFSET_LEFT + (target.y - BASE_COL) * slot_screen
    _idle_guide_hand.offset_top = BASE_OFFSET_TOP + (target.x - BASE_ROW) * slot_screen
    _idle_guide_hand.offset_right = _idle_guide_hand.offset_left + 110.0
    _idle_guide_hand.offset_bottom = _idle_guide_hand.offset_top + 120.0


    var csf: float = get_tree().root.content_scale_factor
    var cell_local_y: float = (BoardView.BOARD_PADDING + target.x * BoardView.SLOT_PX) * _board_view.scale.y
    var cell_top_px: float = (_board_view.global_position.y + cell_local_y) / csf
    var vp_w_px: float = get_viewport_rect().size.x
    var panel_w: float = minf(930.0 / csf, vp_w_px - 60.0 / csf)
    var panel_h: float = 190.0 / csf
    var panel_gap: float = 30.0 / csf
    _idle_guide_msg_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    _idle_guide_msg_panel.size = Vector2(panel_w, panel_h)
    _idle_guide_msg_panel.position = Vector2((vp_w_px - panel_w) / 2.0, cell_top_px - panel_h - panel_gap)

    var hl: String = tr("TUTORIAL_STEP1_HIGHLIGHT")
    var breath_seg: String = "[breath amp=0.03 freq=5 group=1 count=%d][color=#d94848]%s[/color][/breath]" % [hl.length(), hl]
    _idle_guide_msg_rich.text = "[center]" + tr("TUTORIAL_STEP1_RICH").format({"breath": breath_seg}) + "[/center]"
    _idle_guide_msg_rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _idle_guide_msg_rich.offset_left = 30.0 / csf
    _idle_guide_msg_rich.offset_top = 0.0
    _idle_guide_msg_rich.offset_right = -30.0 / csf
    _idle_guide_msg_rich.offset_bottom = 0.0
    _idle_guide_msg_rich.add_theme_font_size_override("normal_font_size", int(48.0 / csf))

    var local_rect: Rect2 = _board_view.cell_to_local_rect(target.x, target.y)
    var board_global: Vector2 = _board_view.global_position
    var cell_top_left: Vector2 = board_global + local_rect.position * board_scale - _idle_mask_layer.global_position
    if _idle_mask_cell != null:
        _idle_mask_cell.queue_free()
        _idle_mask_cell = null
    var src: CellView = _board_view.get_cell_view(target.x, target.y)
    _idle_mask_cell = _CELL_SCENE.instantiate() as CellView
    _idle_mask_cell.pivot_offset_ratio = Vector2.ZERO
    _idle_mask_cell.pivot_offset = Vector2.ZERO
    _idle_mask_cell.position = cell_top_left


    const _HIGHLIGHT_GROW_PX: float = 2.0
    var grow_scale: float = board_scale + _HIGHLIGHT_GROW_PX / BoardView.CELL_PX
    _idle_mask_cell.scale = Vector2(grow_scale, grow_scale)
    _idle_mask_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _idle_mask_layer.add_child(_idle_mask_cell)


    _idle_mask_cell.set_corner_radius_compensated(grow_scale)
    if src != null:
        _idle_mask_cell.set_region_color(src.get_region_color())
    _idle_mask_cell.play_hint()
    _idle_mask_layer.modulate.a = 0.0
    _idle_mask_layer.visible = true
    if _idle_mask_tween != null and _idle_mask_tween.is_valid():
        _idle_mask_tween.kill()
    _idle_mask_tween = create_tween()
    _idle_mask_tween.tween_property(_idle_mask_layer, "modulate:a", 1.0, 0.12)

    _idle_guide_overlay.visible = true
    if _idle_guide_spine.has_method("get_animation_state"):
        _idle_guide_spine.get_animation_state().set_animation("click", true, 0)
    _idle_guide_msg_panel.modulate.a = 0.0
    _idle_guide_msg_panel.scale = Vector2(0.6, 0.6)
    if _idle_guide_tween != null and _idle_guide_tween.is_valid():
        _idle_guide_tween.kill()
    _idle_guide_tween = create_tween().set_parallel(true)
    _idle_guide_tween.tween_property(_idle_guide_msg_panel, "modulate:a", 1.0, 0.25)
    _idle_guide_tween.tween_property(_idle_guide_msg_panel, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK)

func _stop_idle_guide() -> void :
    _hint_mutex.release("idle_guide")
    if _idle_guide_tween != null and _idle_guide_tween.is_valid():
        _idle_guide_tween.kill()
    _idle_guide_tween = null
    if _idle_mask_tween != null and _idle_mask_tween.is_valid():
        _idle_mask_tween.kill()
    _idle_mask_tween = null
    if _idle_mask_cell != null:
        _idle_mask_cell.queue_free()
        _idle_mask_cell = null
    if _idle_mask_layer != null:
        _idle_mask_layer.visible = false
    if _idle_guide_overlay != null:
        _idle_guide_overlay.visible = false

func _reset_idle_hint() -> void :
    super._reset_idle_hint()
    _stop_idle_guide()

func _play_idle_tool_hint() -> void :
    if ABTestManager.idle_guide.suppresses_tool_hint_at_level1() and _level_config.get("level", 0) == 1:
        return
    super._play_idle_tool_hint()


func _try_show_start_toast() -> void :

    if _is_endgame_restore_session:
        return
    var lv: int = _level_config.get("level", 0)
    if not ABTestManager.normal_start_toast.should_show_toast():
        return
    if lv < 11:
        return
    var is_hard: bool = (LevelData.is_hard_level_group_j(lv)
        if ABTestManager.rule_normal_rank.is_group_j()
        else LevelData.is_hard_level(lv))
    var is_first_try: bool = _toast_first_try_hint
    var last_clean: bool = GameState.was_last_level_clean_win()
    var iq_eligible: bool = (ABTestManager.normal_start_toast.should_show_iq_text()
            and not is_hard
            and last_clean
            and is_first_try)



    if iq_eligible:
        var iq_idx: int = _resolve_iq_text_idx(lv)
        _active_toast = _normal_toast
        _active_toast.show_toast({
            "iq_text_key": "GAME_TOAST_IQ_%d" % iq_idx, 
        })
        return

    var pct: float = _resolve_start_toast_pct(lv, is_hard, is_first_try)
    var text_key: String = "GAME_TOAST_FIRST_TRY" if is_first_try else "GAME_TOAST_KEEP_GOING"
    var params: = {
        "text_key": text_key, 
        "pct_str": I18nFormat.percent(pct, 1), 
    }
    _active_toast = _hard_toast if is_hard else _normal_toast
    _active_toast.show_toast(params)


func _resolve_iq_text_idx(lv: int) -> int:
    var cached: int = GameState.get_start_toast_iq_idx(lv)
    if cached > 0:
        return cached
    var idx: int = randi_range(1, 6)
    GameState.set_start_toast_iq_idx(lv, idx)
    return idx



func _resolve_start_toast_pct(lv: int, is_hard: bool, is_first_try: bool) -> float:
    var kind: String = "first_try" if is_first_try else "keep_going"
    var cached: float = GameState.get_start_toast_pct(lv, kind)
    if cached >= 0.0:
        return cached
    var lo: float
    var hi: float
    if is_first_try:
        lo = 40.0 if is_hard else 60.0
        hi = 60.0 if is_hard else 80.0
    else:
        lo = 50.0 if is_hard else 70.0
        hi = 70.0 if is_hard else 90.0
    var pct: float = lo + randf() * (hi - lo)
    GameState.set_start_toast_pct(lv, kind, pct)
    return pct




func _on_gear_btn_pressed() -> void :


    if _is_complete:
        return
    Tracker.track_btn_click(Tracker.Btn.BACK, self)
    _clock_timer.stop()


    var lv: int = _level_config.get("level", 0)
    if lv > 0:
        GameState.mark_current_level_dirty()
    UIManager.show_ui(UiName.HOME)
    UIManager.hide_ui(UiName.GAME)

func _on_restart_requested() -> void :
    _combo_count = 0
    _combo_score = 0
    _hide_auto_complete_btn()
    _exit_draft_mode_and_clear()


    _destroy_banner()



    if _endgame_persist_timer != null and _endgame_persist_timer.time_left > 0.0:
        _endgame_persist_timer.stop()


    var lv: int = _level_config.get("level", 0)
    LevelOps.confirm_level_failed_main(_build_game_end_params(Tracker.GameResult.QUIT), lv)
    LevelOps.on_restart_click()
    if lv > 0:

        var sol_1d: Array = []
        for row: Array in (_puzzle.get("solution", []) as Array):
            var found: bool = false
            for c: int in range(row.size()):
                if row[c]:
                    sol_1d.append(c)
                    found = true
                    break
            if not found:
                sol_1d.append(0)
        on_show({
            "bank_mode": true, 
            "bank_size": _level_config.get("size", 4), 
            "bank_rank": _level_config.get("rank", 1), 
            "bank_index": _level_config.get("bank_idx", 0), 
            "prebuilt_regions": _puzzle.get("regions", []), 
            "prebuilt_solution": sol_1d, 
            "level_seed": _level_config.get("seed", 0), 
            "prefill_positions": _level_config.get("prefill_positions", []), 
            "custom_color_map": _level_config.get("custom_color_map", []), 
            "retry_level": lv, 

            "bank_source_main": _level_config.get("bank_source_main", ""), 
            "bank_tier": _level_config.get("bank_tier", ""), 
            "r1_steps": _strategy_steps[0], 
            "r2_steps": _strategy_steps[1], 
            "r3_steps": _strategy_steps[2], 
            "r4_steps": _strategy_steps[3], 
            "r5_steps": _strategy_steps[4], 
            "_tracker_status": Tracker.GameStatus.RESTART, 
        })
    else:
        var bp: Dictionary = _level_config.get("bank_params", {})
        if not bp.is_empty():
            bp["_tracker_status"] = Tracker.GameStatus.RESTART
            on_show(bp)
        else:
            on_show({"_tracker_status": Tracker.GameStatus.RESTART})












func _on_wrong_guess(r: int, c: int) -> void :
    super._on_wrong_guess(r, c)


    if _lives == 1:
        _board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
        get_tree().create_timer(1.2).timeout.connect( func() -> void :
            _board_view.mouse_filter = Control.MOUSE_FILTER_STOP
            _maybe_show_life_warning()
        )

func _maybe_show_life_warning() -> void :
    if not ABTestManager.warn_life.should_show_life_warning():
        return
    if GameState.has_shown_warn_life():
        return

    GameState.mark_warn_life_shown()
    _show_life_warning()

func _show_life_warning() -> void :
    if _anim_tips == null:
        return
    if not _hint_mutex.try_acquire("warn_life"):
        return
    _warn_phase = 1
    _warn_click_allowed = false

    if _warn_overlay != null:
        _warn_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

    _warn_tips.visible = true

    _align_warn_tail_to_heart()
    _anim_tips.play_section_with_markers("GenericPopup", "", "Mark")

    get_tree().create_timer(0.5).timeout.connect( func() -> void : _warn_click_allowed = true)



func _align_warn_tail_to_heart() -> void :
    if _warn_tail == null or _heart1 == null:
        return

    var heart_center_x: float = _heart1.get_global_rect().get_center().x
    _warn_tail.global_position.x = heart_center_x


func _on_warn_anim_finished(anim_name: StringName) -> void :
    if anim_name != "GenericPopup" or _warn_phase != 2:
        return
    _warn_phase = 0
    _hint_mutex.release("warn_life")
    if _warn_overlay != null:
        _warn_overlay.mouse_filter = Control.MOUSE_FILTER_PASS




func _input(event: InputEvent) -> void :


    if _idle_guide_overlay != null and _idle_guide_overlay.visible:
        var is_guide_press: bool = (event is InputEventScreenTouch and event.pressed)\
or (event is InputEventMouseButton and event.pressed)
        if is_guide_press and _is_press_on_idle_blocked_button(event.position):
            get_viewport().set_input_as_handled()
            return
    if _warn_phase != 1:
        return
    var is_press: bool = (event is InputEventScreenTouch and event.pressed)\
or (event is InputEventMouseButton and event.pressed)
    if not is_press:
        return

    if not _warn_click_allowed:
        get_viewport().set_input_as_handled()
        return
    _warn_phase = 2
    _anim_tips.play_section_with_markers("GenericPopup", "Mark", "")
    get_viewport().set_input_as_handled()



func _is_press_on_idle_blocked_button(screen_pos: Vector2) -> bool:
    for btn in _idle_guide_block_buttons:
        if btn != null and btn.visible and not btn.disabled\
and btn.get_global_rect().has_point(screen_pos):
            return true
    return false


func _reset_life_warning() -> void :
    _hint_mutex.release("warn_life")
    _warn_phase = 0
    if _anim_tips != null and _anim_tips.is_playing():
        _anim_tips.stop()
    if _warn_overlay != null:
        _warn_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
        _warn_overlay.color.a = 0.0
    if _warn_bubble != null:
        _warn_bubble.modulate.a = 0.0
    if _warn_mask != null:
        _warn_mask.modulate.a = 0.0

func _on_game_over() -> void :
    _hide_auto_complete_btn()
    if not _is_complete:
        GameState.on_game_finished()
    _exit_draft_mode_and_clear()
    _is_complete = true
    _clock_timer.stop()
    _stop_idle_tool_hint()
    _destroy_banner()
    Tracker.inc_stat("gamedie_count")

    ABTestManager.dye_at_game_fail_end()

    Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.FAIL))

    _board_view.play_cat_cry_loop_all()
    VibrateManager.play_vibrate(VibrateManager.Level.LEVEL4)
    var lv: int = _level_config.get("level", 0)
    if lv > 0:
        GameState.on_level_failed(lv)

    var retry_params: Dictionary = {}
    if lv > 0:

        var sol_1d: Array = []
        var sol_2d: Array = _puzzle.get("solution", [])
        for row: Array in sol_2d:
            var found: bool = false
            for c: int in range(row.size()):
                if row[c]:
                    sol_1d.append(c)
                    found = true
                    break
            if not found:
                sol_1d.append(0)
        retry_params = {
            "bank_mode": true, 
            "bank_size": _level_config.get("size", 4), 
            "bank_rank": _level_config.get("rank", 1), 
            "bank_index": _level_config.get("bank_idx", 0), 
            "prebuilt_regions": _puzzle.get("regions", []), 
            "prebuilt_solution": sol_1d, 
            "level_seed": _level_config.get("seed", 0), 
            "prefill_positions": _level_config.get("prefill_positions", []), 
            "custom_color_map": _level_config.get("custom_color_map", []), 
            "retry_level": lv, 



            "bank_source_main": _level_config.get("bank_source_main", ""), 
            "bank_tier": _level_config.get("bank_tier", ""), 
            "r1_steps": _strategy_steps[0], 
            "r2_steps": _strategy_steps[1], 
            "r3_steps": _strategy_steps[2], 
            "r4_steps": _strategy_steps[3], 
            "r5_steps": _strategy_steps[4], 
        }

        GameState.set_retry_puzzle(lv, retry_params)
    else:

        var bp: Dictionary = _level_config.get("bank_params", {})
        if not bp.is_empty():
            retry_params = bp.duplicate()
        else:
            retry_params = {"level_index": 1}

    var _sz: int = _level_config.get("size", 4)
    var _placed: int = 0
    if _draft_deadlock_pending:


        _placed = (_draft_deadlock_real_marks.get("placed_cats", []) as Array).size()
    else:
        for _r in range(_sz):
            for _c in range(_sz):
                if _board_view.get_cell_state(_r, _c) == CellState.CAT:
                    _placed += 1
    var remaining_cats: int = _sz - _placed
    var fail: = UIManager.show_ui(UiName.FAIL, {
        "level_config": _level_config, 
        "retry_params": retry_params, 
        "remaining_cats": remaining_cats, 
    })
    if fail != null and not fail.revive_requested.is_connected(_on_revive_requested):
        fail.revive_requested.connect(_on_revive_requested)
    if fail != null and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
        fail.revive_ad_started.connect(_on_revive_ad_started)




func _on_revive_ad_started() -> void :
    _board_view.revive_all_cat_to_idle()

func _on_revive_requested() -> void :
    UIManager.hide_ui(UiName.FAIL)
    _is_complete = false
    _revive_count += 1
    GameState.mark_dda_tool_or_revive_used()
    GameState.mark_dda_revive_used()
    GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "revive_count")
    GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "rv_count")

    _lives = mini(_lives + ABTestManager.revive_life.get_lives_to_restore(), 3)
    _refresh_hearts()



    if ABTestManager.revive_life.get_lives_to_restore() >= 3:
        for slot: LifeSlot in [_heart1, _heart2, _heart3]:
            if slot != null:
                slot.play_revive()


    if _draft_deadlock_pending:
        _rollback_draft_deadlock()
        _clear_draft_deadlock_state()

    _flush_endgame_snapshot()

    _like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

    _board_view.revive_all_cat_to_idle()

    _show_banner_if_eligible("game")

    if ABTestManager.idle_guide.is_step_trigger_enabled() and _level_config.get("level", 0) == 1:
        if _step_history.size() >= 3 and not _step_trigger_had_cat and not _is_complete and not _hint_overlay.visible:
            _idle_guide_shown = false
            _show_idle_guide()



func _on_game_complete() -> void :
    _hide_auto_complete_btn()
    if not _is_complete:
        GameState.on_game_finished()


    _exit_draft_mode_and_clear(ABTestManager.draft_mode.keep_marks_on_manual_exit())
    _is_complete = true
    _clock_timer.stop()
    _stop_idle_tool_hint()
    _destroy_banner()

    Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.WIN))



    SoundManager.stop(SoundManager.Kind.MARK_CAT)
    _board_view.replay_all_cat_appear()
    VibrateManager.play_vibrate(VibrateManager.Level.LEVEL5)
    _cleanup_hint()
    await get_tree().process_frame
    var lv: int = _level_config.get("level", 0)

    _level_config["restart_count"] = _restart_count
    _level_config["revive_count"] = _revive_count
    _level_config["mistake_count"] = _mistake_count
    if lv > 0:


        GameState.on_level_won(lv)







    _level_config["elapsed_sec"] = _like_hand_state.get("in_game_sec", 0.0)







    var toast_was_shown: bool = await _play_win_toast_and_wait()
    _level_config["toast_was_shown"] = toast_was_shown
    var streak_consumed_appear_delay: bool = await _try_run_streak_flow_after_win(&"main", toast_was_shown)
    _level_config["skip_appear_delay"] = streak_consumed_appear_delay
    UIManager.show_ui(_win_ui_name(), {"level_config": _level_config, "board_view": _board_view})

func _win_ui_name() -> StringName:
    return UiName.WIN














func _try_run_streak_flow_after_win(source: StringName, skip_cat_appear: bool = false) -> bool:
    StreakManager.notify_win(source)
    if not StreakManager.has_pending_show():
        return false
    if not skip_cat_appear:
        await get_tree().create_timer(GameWinPage.APPEAR_DELAY).timeout
    var streak_page: StreakPage

    if StreakManager.get_data().current_streak == 1 and not StreakManager.should_skip_lit():
        streak_page = StreakPage.open_lit()
    else:
        streak_page = StreakPage.open_settle()
    while is_instance_valid(streak_page) and streak_page.visible:
        await streak_page.visibility_changed
    return true





const _SIZE_CYCLE_CTRL_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_CTRL_11_20: Array[int] = [6, 6, 8, 8, 10, 8, 9, 10, 9, 8]
const _SIZE_CYCLE_CTRL_21_50: Array[int] = [8, 9, 10, 9, 10, 8, 9, 10, 9, 10]
const _SIZE_CYCLE_CTRL_51_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]


const _SIZE_CYCLE_A_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_A_11_20: Array[int] = [6, 6, 8, 8, 10, 8, 9, 10, 9, 8]
const _SIZE_CYCLE_A_21_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]


const _SIZE_CYCLE_B_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_B_11_20: Array[int] = [6, 6, 8, 8, 9, 8, 9, 8, 9, 8]
const _SIZE_CYCLE_B_21_50: Array[int] = [8, 9, 9, 8, 9, 9, 8, 9, 9, 10]
const _SIZE_CYCLE_B_51_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]


const _SIZE_CYCLE_C_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_C_11_20: Array[int] = [6, 6, 8, 8, 9, 8, 9, 8, 9, 8]
const _SIZE_CYCLE_C_21_100: Array[int] = [8, 9, 9, 8, 9, 9, 8, 9, 9, 10]
const _SIZE_CYCLE_C_101_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]


const _SIZE_CYCLE_D_1_10: Array[int] = [4, 5, 6, 6, 8, 6, 7, 8, 9, 7]
const _SIZE_CYCLE_D_11_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]


const _SIZE_CYCLE_E_1_10: Array[int] = [4, 4, 6, 6, 8, 6, 6, 8, 8, 7]
const _SIZE_CYCLE_E_11_20: Array[int] = [6, 6, 8, 8, 10, 8, 9, 10, 9, 8]
const _SIZE_CYCLE_E_21_50: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_E_51_PLUS: Array[int] = [8, 10, 11, 9, 10, 11, 9, 10, 11, 10]


const _SIZE_CYCLE_F_1_10: Array[int] = [4, 5, 6, 6, 8, 6, 7, 8, 9, 7]
const _SIZE_CYCLE_F_11_50: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]
const _SIZE_CYCLE_F_51_PLUS: Array[int] = [8, 10, 11, 9, 10, 11, 9, 10, 11, 10]

func _get_ab_size(level_num: int) -> int:
    match _size_cycle:
        3:
            if level_num <= 10:
                return _SIZE_CYCLE_A_1_10[level_num - 1]
            if level_num <= 20:
                return _SIZE_CYCLE_A_11_20[level_num - 11]
            return _SIZE_CYCLE_A_21_PLUS[(level_num - 21) % 10]
        4:
            if level_num <= 10:
                return _SIZE_CYCLE_B_1_10[level_num - 1]
            if level_num <= 20:
                return _SIZE_CYCLE_B_11_20[level_num - 11]
            if level_num <= 50:
                return _SIZE_CYCLE_B_21_50[(level_num - 21) % 10]
            return _SIZE_CYCLE_B_51_PLUS[(level_num - 51) % 10]
        5:
            if level_num <= 10:
                return _SIZE_CYCLE_C_1_10[level_num - 1]
            if level_num <= 20:
                return _SIZE_CYCLE_C_11_20[level_num - 11]
            if level_num <= 100:
                return _SIZE_CYCLE_C_21_100[(level_num - 21) % 10]
            return _SIZE_CYCLE_C_101_PLUS[(level_num - 101) % 10]
        6:
            if level_num <= 10:
                return _SIZE_CYCLE_D_1_10[level_num - 1]
            return _SIZE_CYCLE_D_11_PLUS[(level_num - 11) % 10]
        7:
            if level_num <= 10:
                return _SIZE_CYCLE_E_1_10[level_num - 1]
            if level_num <= 20:
                return _SIZE_CYCLE_E_11_20[level_num - 11]
            if level_num <= 50:
                return _SIZE_CYCLE_E_21_50[(level_num - 21) % 10]
            return _SIZE_CYCLE_E_51_PLUS[(level_num - 51) % 10]
        8:
            if level_num <= 10:
                return _SIZE_CYCLE_F_1_10[level_num - 1]
            if level_num <= 50:
                return _SIZE_CYCLE_F_11_50[(level_num - 11) % 10]
            return _SIZE_CYCLE_F_51_PLUS[(level_num - 51) % 10]
        _:
            if level_num <= 10:
                return _SIZE_CYCLE_CTRL_1_10[level_num - 1]
            if level_num <= 20:
                return _SIZE_CYCLE_CTRL_11_20[level_num - 11]
            if level_num <= 50:
                return _SIZE_CYCLE_CTRL_21_50[(level_num - 21) % 10]
            return _SIZE_CYCLE_CTRL_51_PLUS[(level_num - 51) % 10]





func _on_rule_violated(rule: int) -> void :
    var cfg: = ABTestManager.rule_highlight
    if not cfg.is_highlight_violated():
        return
    if not cfg.is_all_levels():

        if not GameState.is_tutorial_done():
            return
        if GameState.get_current_level() > 5:
            return

    _play_rule_highlight(rule)

func _prefill_hints() -> void :
    var positions: Array = _level_config.get("prefill_positions", [])
    for pos in positions:
        var r: int = pos[0]
        var c: int = pos[1]

        _board_view.set_cell_state(r, c, CellState.CAT, false, true, BoardView.ChangeSource.PREFILL)







func _auto_mark_prefill_cats() -> void :
    if _is_endgame_restore_session:
        return
    if not ABTestManager.game_auto_mark.prefill_auto_cross_enabled_at(_current_level()):
        return
    var sz: int = _level_config.get("size", 0)
    if sz <= 0:
        return
    for pos in _level_config.get("prefill_positions", []):
        var cat: = Vector2i(pos[0], pos[1])
        if _board_view.get_cell_state(cat.x, cat.y) == CellState.CAT:

            _spread_auto_cross(cat, 0.0, QueendokuCore.cells_excluded_by_cat(cat, sz, _puzzle["regions"]))





func _maybe_show_auto_mark_tutorial() -> void :
    if _auto_mark_tutorial_overlay != null:
        return
    if ABTestManager == null or ABTestManager.game_auto_mark == null:
        return
    if not ABTestManager.game_auto_mark.is_dot_toggle_enabled_at(_current_level()):
        return
    if GameState.is_auto_mark_tutorial_done():
        return
    if _board_view == null or _board_view.get_puzzle_size() <= _AUTO_MARK_TUTORIAL_COL:
        return



    await _wait_start_toast_hidden_if_any()

    if _entry_anim_playing:
        return
    if not visible or _is_complete or _wrong_guess_pending:
        return
    if _auto_mark_tutorial_overlay != null or GameState.is_auto_mark_tutorial_done():
        return
    if _board_view == null or not is_instance_valid(_board_view):
        return
    _auto_mark_tutorial_overlay = _AUTO_MARK_TUTORIAL_SCENE.instantiate() as AutoMarkTutorialOverlay
    add_child(_auto_mark_tutorial_overlay)
    _auto_mark_tutorial_overlay.closed.connect(_on_auto_mark_tutorial_closed)
    _auto_mark_tutorial_overlay.setup(_board_view, _AUTO_MARK_TUTORIAL_COL)


    var _is_marked_before: bool = _board_view.is_axis_auto_mark_marked(1, _AUTO_MARK_TUTORIAL_COL)
    _on_axis_auto_mark_pressed(1, _AUTO_MARK_TUTORIAL_COL, _is_marked_before)





func _on_auto_mark_tutorial_closed(_hit_btn: bool) -> void :
    GameState.mark_auto_mark_tutorial_done()
    _free_auto_mark_tutorial_overlay()
    await _wait_axis_idle_for_tutorial_uncross(_AUTO_MARK_TUTORIAL_COL)

    if not is_inside_tree() or not visible or not is_instance_valid(_board_view):
        return
    if not _board_view.is_axis_auto_mark_marked(1, _AUTO_MARK_TUTORIAL_COL):
        return
    _on_axis_auto_mark_pressed(1, _AUTO_MARK_TUTORIAL_COL, true)



func _wait_axis_idle_for_tutorial_uncross(col: int) -> void :
    var token: int = _auto_mark_token
    var key: String = _axis_key(1, col)
    while _axis_busy_set.has(key):
        await get_tree().process_frame
        if token != _auto_mark_token or not is_inside_tree():
            return



func _free_auto_mark_tutorial_overlay() -> void :
    if _auto_mark_tutorial_overlay == null:
        return
    if is_instance_valid(_auto_mark_tutorial_overlay):
        _auto_mark_tutorial_overlay.queue_free()
    _auto_mark_tutorial_overlay = null



func _restore_partial_board() -> void :
    _restore_partial_board_from(_level_config.get("restore_state", {}))



func _restore_partial_board_from(data: Dictionary) -> void :
    if data.is_empty():
        return
    for pos in data.get("placed_cats", []):
        _board_view.set_cell_state(int(pos[0]), int(pos[1]), CellState.CAT, false, true, BoardView.ChangeSource.RESTORE)
    for pos in data.get("marks", []):
        _board_view.set_cell_state(int(pos[0]), int(pos[1]), CellState.MARK, false, true, BoardView.ChangeSource.RESTORE)


    for pos in data.get("errors", []):
        var r: int = int(pos[0])
        var c: int = int(pos[1])
        _board_view.set_cell_state(r, c, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE)
        _board_view.mark_cell_error(r, c, BoardView.ChangeSource.RESTORE)






    var lock_x_on: bool = (ABTestManager != null and ABTestManager.game_auto_mark != null
        and ABTestManager.game_auto_mark.is_lock_x_enabled_at(_current_level()))
    for pos in data.get("locked_marks", []):
        var lr: int = int(pos[0])
        var lc: int = int(pos[1])
        _board_view.set_cell_state(lr, lc, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE)
        if lock_x_on:
            _board_view.lock_mark(lr, lc, "StatusLock", false, BoardView.ChangeSource.RESTORE)



func _compute_color_map_for_current(sz: int) -> Array[int]:
    var raw_cm: Array = _level_config.get("custom_color_map", \
_level_config.get("bank_params", {}).get("custom_color_map", []))
    var color_map: Array[int]
    if raw_cm.size() == sz:
        color_map = []
        for v in raw_cm:
            color_map.append(int(v))
    else:
        var color_seed: int = _level_config.get("_bank_transform", 
            _level_config.get("bank_params", {}).get("_bank_transform", 0))
        color_map = LevelGenerator.compute_color_map_with_seed(sz, _puzzle["regions"], color_seed)
    return color_map





func _rollback_draft_deadlock() -> void :
    if _board_view == null:
        return
    var sz: int = _level_config.get("size", 0)
    if sz <= 0:
        return
    var _pat_regions_rb: Array = _level_config.get("patternRegions", [])
    _board_view.setup(sz, _puzzle["regions"], _compute_color_map_for_current(sz), _pat_regions_rb, true)
    _prefill_hints()
    _restore_partial_board_from(_draft_deadlock_real_marks)
    _seed_like_hand_first_cat_from_board()
    _board_view.visible = true
    _board_view.mouse_filter = Control.MOUSE_FILTER_STOP
    _update_remaining()



func _on_cheat_command(cmd_name: String, args: Array[String]) -> void :
    match cmd_name:
        "win": _cmd_win(args)
        "draft_win": _cmd_draft_win(args)
        "level": _cmd_level(args)
        "lives": _cmd_lives(args)
        "lifeplus": _cmd_lifeplus(args)
        "dumpjson": _cmd_dumpjson(args)



func _cmd_lifeplus(args: Array[String]) -> void :
    var first: bool = args.is_empty() or args[0] != "0"
    _play_life_plus_fx(first)




func _cmd_win(_args: Array[String]) -> void :
    if _entry_anim_playing or _is_complete or _wrong_guess_pending or _auto_completing:
        return
    if _puzzle.is_empty() or not _puzzle.has("solution"):
        return
    _auto_completing = true
    _auto_complete_token += 1
    _hide_auto_complete_btn()
    _reset_idle_hint()
    _exit_draft_mode_and_clear(true)
    UIMask.acquire()
    await _run_auto_complete(_auto_complete_token)
    UIMask.release()
    _auto_completing = false



func _cmd_draft_win(_args: Array[String]) -> void :
    if _is_complete:
        return
    if not _draft_mode:
        _enter_draft_mode()
    var sz: int = _level_config.get("size", 0)
    var sol: Array = _puzzle.get("solution", [])
    for r: int in range(sz):
        for c: int in range(sz):
            if not bool(sol[r][c]):
                continue
            if _board_view.get_cell_state(r, c) == CellState.CAT:
                continue
            _set_cell_draft(r, c, CellState.DRAFT_CAT)
    _apply_draft_commit()

func _cmd_level(_args: Array[String]) -> void :
    pass

func _cmd_dumpjson(args: Array[String]) -> void :


    var mode: int = int(args[0]) if args.size() > 0 else 1
    var base: Dictionary
    if mode == 0:
        base = _build_endgame_snapshot()
    else:
        base = _build_puzzle_base()
        base["prefill_positions"] = _level_config.get("prefill_positions", [])
    var json: String = JSON.stringify(base)
    print("[Cheat dumpjson mode=%d]\n%s" % [mode, json])
    DisplayServer.clipboard_set(json)
    Toast.popup("题目 JSON 已复制到剪贴板", self)




func _build_puzzle_base() -> Dictionary:
    var sz: int = _level_config.get("size", 0)
    var region_map: Array = _puzzle.get("regions", [])

    var sol_1d: Array = []
    for row: Array in (_puzzle.get("solution", []) as Array):
        var col: int = -1
        for c: int in range(row.size()):
            if row[c]:
                col = c
                break
        sol_1d.append(col)
    return {
        "size": sz, 
        "r": _level_config.get("rank", 0), 
        "id": _level_config.get("bank_idx", _level_config.get("level", 0)), 
        "seed": _level_config.get("seed", 0), 
        "regionMap": region_map, 
        "solution": sol_1d, 
    }






func _build_endgame_snapshot() -> Dictionary:
    var base: Dictionary = _build_puzzle_base()
    var sz: int = int(base["size"])
    var board: Array = _board_view.get_board()
    var placed_cats: Array = []
    var marks: Array = []
    var errors: Array = []
    var locked_marks: Array = []
    for r: int in range(sz):
        for c: int in range(sz):
            var st: int = board[r][c]
            match st:
                CellState.CAT:
                    placed_cats.append([r, c])
                CellState.MARK:
                    marks.append([r, c])
                CellState.ERROR:
                    errors.append([r, c])
                CellState.LOCKED_MARK:
                    locked_marks.append([r, c])


    var snapshot: Dictionary = {"version": GameState.ENDGAME_SNAPSHOT_VERSION}
    snapshot.merge(base)


    snapshot["level"] = int(_level_config.get("level", 0))
    snapshot["bank_source"] = _level_config.get("bank_source", "")
    snapshot["bank_source_main"] = _level_config.get("bank_source_main", "")
    snapshot["bank_tier"] = _level_config.get("bank_tier", "")
    snapshot["prefill_positions"] = _level_config.get("prefill_positions", [])
    snapshot["lives"] = _lives
    snapshot["placed_cats"] = placed_cats
    snapshot["marks"] = marks
    snapshot["errors"] = errors



    snapshot["locked_marks"] = locked_marks

    snapshot["draft_marks"] = _serialize_draft_marks()

    snapshot["step_history"] = _step_history.serialize()
    snapshot["combo_count"] = _combo_count
    snapshot["combo_score"] = _combo_score
    snapshot["restart_count"] = _restart_count
    snapshot["revive_count"] = _revive_count

    snapshot["life_plus_used"] = _life_plus_used_this_game
    return snapshot




func _on_auto_mark_preset_done() -> void :
    if _endgame_persist_timer == null:
        return
    if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
        return
    _endgame_persist_timer.stop()
    _flush_endgame_snapshot()





func _on_draft_changed_for_persist(immediate: bool = false) -> void :
    if ABTestManager.draft_mode.value() != ABTestManager.draft_mode.VALUE_AUTO_WIN_PERSIST:
        return
    if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
        return
    if immediate:
        _endgame_persist_timer.stop()
        _flush_endgame_snapshot()
    else:
        _endgame_persist_timer.start()


func _try_restore_draft_marks_from_snapshot() -> void :
    if ABTestManager.draft_mode.value() != ABTestManager.draft_mode.VALUE_AUTO_WIN_PERSIST:
        return



    if not _is_endgame_restore_session:
        return
    var snapshot: Dictionary = GameState.get_endgame_snapshot()
    if snapshot.is_empty():
        return
    var data: Array = snapshot.get("draft_marks", []) as Array
    if data.is_empty():
        return
    _restore_draft_marks_from_snapshot(data)



func _should_show_draft_onboarding_now() -> bool:
    return (_level_config.get("level", 0) >= 21
        and _is_draft_unlocked()
        and not GameState.has_shown_draft_onboarding())




func _try_show_draft_onboarding_after_appear() -> void :


    await _wait_start_toast_hidden_if_any()



    if _entry_anim_playing:
        return

    if not visible or _is_complete or _wrong_guess_pending:
        _unlock_board_after_onboarding_skipped()
        return
    if GameState.has_shown_draft_onboarding():
        _unlock_board_after_onboarding_skipped()
        return
    var tooltip: DraftOnboardingTooltip = _show_draft_onboarding()
    if tooltip == null:
        _unlock_board_after_onboarding_skipped()
        return

    tooltip.tree_exited.connect(_unlock_board_after_onboarding_skipped)




func _wait_start_toast_hidden_if_any() -> void :
    var active: BaseGameToast = _active_toast
    if active == null or not active.visible:
        return
    while active.visible:
        await active.visibility_changed




func _lock_entry_buttons() -> void :
    _entry_btn_lock_seq += 1
    for b in _entry_locked_buttons:
        if is_instance_valid(b):
            b.mouse_filter = Control.MOUSE_FILTER_IGNORE



func _unlock_entry_buttons() -> void :
    for b in _entry_locked_buttons:
        if is_instance_valid(b):
            b.mouse_filter = Control.MOUSE_FILTER_STOP




func _unlock_entry_buttons_after_toast(seq: int) -> void :
    await _wait_start_toast_hidden_if_any()
    if seq != _entry_btn_lock_seq:
        return
    _unlock_entry_buttons()



func _unlock_board_after_onboarding_skipped() -> void :
    if _board_view != null and is_instance_valid(_board_view):
        _board_view.mouse_filter = Control.MOUSE_FILTER_STOP

const _DRAFT_ONBOARDING_TOOLTIP_SCENE: PackedScene = preload("res://scripts/module/game/ui/draft_onboarding_tooltip.tscn")



func _show_draft_onboarding() -> DraftOnboardingTooltip:
    if _draft_btn == null:
        return null
    var tooltip: DraftOnboardingTooltip = _DRAFT_ONBOARDING_TOOLTIP_SCENE.instantiate() as DraftOnboardingTooltip

    get_tree().root.add_child(tooltip)


    var btn_xform: Transform2D = _draft_btn.get_global_transform()
    var visual_tl: Vector2 = btn_xform * Vector2.ZERO
    var visual_br: Vector2 = btn_xform * _draft_btn.size
    var visual_rect: Rect2 = Rect2(visual_tl, visual_br - visual_tl)
    tooltip.show_at(visual_rect)

    tooltip.hit_draft_btn.connect(_on_draft_btn_pressed, CONNECT_ONE_SHOT)
    return tooltip




func _persist_endgame_snapshot(_r: int, _c: int, state: int, _source: int = 0) -> void :
    if state == CellState.CAT or state == CellState.ERROR:
        _endgame_persist_timer.stop()


        call_deferred("_flush_endgame_snapshot")
    else:
        _endgame_persist_timer.start()

func _flush_endgame_snapshot() -> void :
    GameState.set_endgame_snapshot(_build_endgame_snapshot())



func _on_prev_btn_pressed() -> void :
    _exit_draft_mode_and_clear()
    _nav_to(_nav_index - 1)

func _on_next_btn_pressed() -> void :
    _exit_draft_mode_and_clear()
    _nav_to(_nav_index + 1)

func _nav_to(new_index: int) -> void :
    if _nav_total <= 0:
        return
    var idx: int = ((new_index - 1) % _nav_total + _nav_total) % _nav_total + 1

    var bp: Dictionary = _level_config.get("bank_params", {})
    if bp.is_empty():

        UIManager.show_ui(UiName.GAME, {"level_index": idx})
        return


    var is_lk: bool = bp.get("bank_lk", false)
    var is_lk_style: bool = bp.get("bank_lk_style", false)
    var is_sp: bool = bp.get("bank_sp", false)
    var sz: int = bp.get("bank_size", 7)
    var rank: int = bp.get("bank_rank", 1)

    var is_tier_h: bool = bp.get("bank_tier_h", false)
    var bank_tier: String = bp.get("bank_tier", "")
    var is_gc: bool = bp.get("bank_gc", false)
    var levels: Array
    if is_sp:
        levels = BankData.get_sp_levels()
    elif is_lk:
        var is_lk_modified: bool = bp.get("bank_lk_modified", false)
        levels = BankData.get_lk_modified_levels() if is_lk_modified else BankData.get_lk_levels()
    elif is_gc:
        if bank_tier == "H" or bank_tier == "N":
            levels = BankData.get_gc_levels_by_tier(sz, rank, bank_tier)
        else:
            levels = BankData.get_gc_levels(sz, rank)
    elif is_lk_style:
        if bank_tier == "H" or bank_tier == "N":
            levels = BankData.get_lk_style_levels_by_tier(sz, rank, bank_tier)
        else:
            levels = BankData.get_lk_style_levels(sz, rank)
    else:
        if bank_tier == "H" or bank_tier == "N":
            levels = BankData.get_levels_by_tier(sz, rank, bank_tier)
        else:
            levels = BankData.get_levels(sz, rank)

    if levels.is_empty() or idx - 1 >= levels.size():
        return

    var entry: Dictionary = levels[idx - 1]
    var new_params: Dictionary = bp.duplicate()
    new_params["bank_index"] = idx
    new_params["prebuilt_regions"] = entry.get("regionMap", [])
    new_params["prebuilt_solution"] = entry.get("solution", [])

    if is_sp:
        new_params["bank_size"] = entry.get("size", 9)
        new_params["bank_rank"] = entry.get("r", 1)
        new_params["level_seed"] = entry.get("id", 0)
        new_params["custom_color_map"] = entry.get("colorMap", [])
        new_params["r1_steps"] = entry.get("r1", 0)
        new_params["r2_steps"] = entry.get("r2", 0)
        new_params["r3_steps"] = entry.get("r3", 0)
        new_params["r4_steps"] = entry.get("r4", 0)
        new_params["r5_steps"] = entry.get("r5", 0)
    elif is_lk:
        new_params["bank_size"] = entry.get("size", 8)
        new_params["bank_rank"] = entry.get("maxR", 1)
        new_params["level_seed"] = entry.get("id", 0)
    else:
        new_params["level_seed"] = entry.get("seed", 0)
        new_params["r1_steps"] = entry.get("r1", 0)
        new_params["r2_steps"] = entry.get("r2", 0)
        new_params["r3_steps"] = entry.get("r3", 0)
        new_params["r4_steps"] = entry.get("r4", 0)
        new_params["r5_steps"] = entry.get("r5", 0)

    UIManager.show_ui(UiName.GAME, new_params)









func get_scr_name() -> String:
    return Tracker.Scr.NORMAL_GAME



func _build_game_end_params(result: String) -> Dictionary:
    var time_sec: int = (Time.get_ticks_msec() - _stat_start_ms) / 1000


    GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "time_total", time_sec)
    var sz: int = _level_config.get("size", 0)
    var cat_n: int = _board_view.count_cat_cells()
    return {
        "qid": _build_qid(), 
        "qrotate": Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)), 
        "result": result, 
        "game_type": Tracker.GameType.NORMAL, 
        "diffi": _get_diffi(), 
        "level": _level_config.get("level", 0), 
        "strategy_layer": _level_config.get("rank", 0), 
        "scale": sz, 
        "hint": GameState.get_tool_count("hint"), 
        "locate": GameState.get_tool_count("locate"), 
        "hint_used": Tracker.get_stat("hint_used"), 
        "locate_used": Tracker.get_stat("locate_used"), 
        "hint_used_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "hint_used_total"), 
        "locate_used_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "locate_used_total"), 
        "hint_apply_used": Tracker.get_stat("hint_apply_used"), 
        "hint_stop_used": Tracker.get_stat("hint_stop_used"), 
        "hint_detail_used": Tracker.get_stat("hint_detail_used"), 
        "clear_used": Tracker.get_stat("clear_used"), 
        "clear_used_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "clear_used_total"), 
        "draft_used_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_used_total"), 
        "draft_time_total": int(GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_time_total_ms") / 1000.0), 
        "draft_error_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_error_total"), 
        "draft_correct_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_correct_total"), 
        "coord_count": Tracker.get_stat("coord_count"), 
        "step_used": Tracker.get_stat("step_used"), 
        "step_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "step_total"), 
        "gamedie_count": Tracker.get_stat("gamedie_count"), 
        "restart_count": Tracker.get_stat("restart_count"), 
        "time": time_sec, 
        "time_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "time_total"), 
        "cross_count": _board_view.count_mark_cells(), 
        "invalid_sign": _board_view.count_error_cells(), 
        "invalid_sign_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "invalid_sign_total"), 
        "fail_sign": sz - cat_n, 
        "erase_count": Tracker.get_stat("erase_count"), 
        "revive_count": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "revive_count"), 
        "rv_count": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "rv_count"), 
        "hp_count": _lives, 
    }
