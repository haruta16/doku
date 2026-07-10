@tool
class_name GameWinPage
extends UIFrameWindow

@onready var _overlay: ColorRect = $Root / Overlay
@onready var _ray_light: TextureRect = $Root / Ctrl / RayLight
@onready var _confetti: TextureRect = $Root / Ctrl / Confetti
@onready var _cat: SpineSprite = $Root / Ctrl / VictoryCat
@onready var _title: Label = $Root / Ctrl / TitleLabel
@onready var _next_btn: Control = $Root / Ctrl / VBoxContainer / NextBtn
@onready var _continue_btn: Button = $Root / Ctrl / VBoxContainer / ContinueBtn
@onready var _beat_percent_label: RichTextLabel = $Root / Ctrl / VBoxContainer / BeatPercentLabel
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _anim_loop: AnimationPlayer = $AnimationPlayer2

const APPEAR_DELAY: float = 1.2

const APPEAR_DURATION: float = 2.467

const WIN_TITLES_NORMAL: Array[StringName] = [
    &"WIN_TITLE", &"WIN_TITLE_1", &"WIN_TITLE_2", &"WIN_TITLE_3", &"WIN_TITLE_4"
]

var _level_config: Dictionary = {}
var _last_win_title: StringName = &""

var _pass_text_strategy: PassTextStrategy

var _win_text: Dictionary = {}

var _show_seq_id: int = 0

func _ready() -> void :
    if Engine.is_editor_hint():

        visible = true
        _overlay.color.a = 0.8
        _ray_light.modulate.a = 0.7
        _confetti.modulate.a = 1.0
        _cat.scale = Vector2.ONE
        _title.modulate.a = 1.0
        _next_btn.modulate.a = 1.0
        return
    bind_press_release_scale($Root / Ctrl / BankBtn)



func on_show(params: Dictionary = {}) -> void :

    _pass_text_strategy = PassTextStrategy.create()
    var lc: Dictionary = params.get("level_config", {})
    var lv: int = lc.get("level", 0)

    if ABTestManager.rate_us_pop.is_eligible_at_game_win(lv, GameState.get_session_consecutive_wins()) and not GameState.has_shown_rate_us():
        UIManager.block_input_briefly(self, APPEAR_DELAY + APPEAR_DURATION)
    else:
        UIManager.block_input_briefly(self, 2.0)
    var bv: BoardView = params.get("board_view")
    if bv != null:
        show_win(lc, bv)



func on_hide() -> void :
    if not visible:
        return

    _show_seq_id += 1
    _anim_loop.stop()
    _anim.play("Disappear")
    await _anim.animation_finished



    _reset_cat_spine()
    visible = false



func show_win(level_config: Dictionary, board_view: BoardView) -> void :
    _level_config = level_config
    _show_seq_id += 1
    var seq: int = _show_seq_id
    visible = true



    _level_config["last_win_beat_percent"] = GameState.get_last_win_beat_percent()
    _win_text = _pass_text_strategy.get_win_text(_level_config)
    if not _level_config.get("is_daily", false):
        GameState.set_last_win_beat_percent(_win_text.get("shown_percent", -1.0))


    _setup_win_title()
    _setup_next_btn()
    _maybe_show_stats_label()
    _maybe_show_beat_percent_tip()



    _delayed_maybe_show_rate_us(seq)



    _reset_cat_spine()





    _anim.stop()
    _anim.play("Appear")
    _anim.advance(0.0)
    _anim.pause()





    if not level_config.get("skip_appear_delay", false) and not level_config.get("toast_was_shown", false):
        await get_tree().create_timer(APPEAR_DELAY).timeout
        if seq != _show_seq_id:
            return
    SoundManager.play(SoundManager.Kind.LEVEL_WIN)
    _resume_cat_spine()
    _anim.play("Appear")

    _anim.advance(0.0)
    _cat.update_skeleton(0.0)
    await _anim.animation_finished
    if seq != _show_seq_id:
        return


    _anim.play("Loop")


    _anim_loop.play("ContinueLoop")








func _reset_cat_spine() -> void :
    if _cat == null:
        return
    _cat.visible = true
    var st: = _cat.get_animation_state()
    if st != null:
        st.set_animation("appear", false, 0)
        st.set_time_scale(0.0)
    _cat.update_skeleton(0.0)
    _cat.visible = false


func _resume_cat_spine() -> void :
    if _cat == null:
        return
    var st: = _cat.get_animation_state()
    if st != null:
        st.set_time_scale(1.0)



func _delayed_maybe_show_rate_us(seq: int) -> void :

    var lv: int = _level_config.get("level", 0)
    if not ABTestManager.rate_us_pop.is_eligible_at_game_win(lv, GameState.get_session_consecutive_wins()) or GameState.has_shown_rate_us():
        return


    if not UniKitManager.is_online():
        return
    if seq != _show_seq_id:
        return
    GameState.mark_rate_us_shown()
    _next_btn.modulate.a = 0.0

    await get_tree().create_timer(APPEAR_DELAY + APPEAR_DURATION).timeout
    if seq != _show_seq_id:
        return
    await _run_rate_us_flow()
    _restore_next_btn()

func _run_rate_us_flow() -> void :



    var page_key: StringName = UiName.RATE_US_V2 if ABTestManager.rate_us_pop_ui.is_new_ui() else UiName.RATE_US
    var rate_us: = UIManager.show_ui(page_key)
    var data: Dictionary = await rate_us.closed
    UIManager.hide_ui(page_key)
    if data.get("is_submitted") and data.get("star_count", 0) > 4:


        InAppReviewManager.request_review()
    elif data.get("is_submitted") and data.get("star_count", 0) <= 4:
        var feedback: = UIManager.show_ui(UiName.FEEDBACK, {"as_dlg": true})
        await feedback.closed
        UIManager.hide_ui(UiName.FEEDBACK)

func _restore_next_btn() -> void :
    var tw: = create_tween()
    tw.tween_property(_next_btn, "modulate:a", 1.0, 0.25)



func _setup_win_title() -> void :

    var override_title: String = _win_text.get("title", "")
    if not override_title.is_empty():
        _title.text = override_title
        return
    var lv: int = _level_config.get("level", 0)
    var key: StringName
    var _is_hard: bool = LevelData.is_hard_level_group_j(lv) if ABTestManager.rule_normal_rank.is_group_j() else LevelData.is_hard_level(lv)
    if lv > 0 and _is_hard:
        key = &"WIN_TITLE_HARD"
    else:
        var pool: = WIN_TITLES_NORMAL.filter( func(k: StringName) -> bool: return k != _last_win_title)
        key = pool[randi() % pool.size()]
    _last_win_title = key
    _title.text = tr(key)



func _setup_next_btn() -> void :

    _continue_btn.visible = _level_config.get("is_daily", false)

    if _level_config.get("is_daily", false):
        _next_btn.visible = false
        return
    var lv: int = _level_config.get("level", 0)
    if lv > 0:
        _next_btn.visible = true
        var next_lv: int = lv + 1
        _next_btn.btn_text = tr("GAME_LEVEL_TITLE") % next_lv
        _next_btn.show_difficult = LevelData.is_hard_level_group_j(next_lv) if ABTestManager.rule_normal_rank.is_group_j() else LevelData.is_hard_level(next_lv)
    else:
        var bp: Dictionary = _level_config.get("bank_params", {})
        if not bp.is_empty():
            _next_btn.visible = true
            _next_btn.show_difficult = false
            var idx: int = bp.get("bank_index", 1)
            var total: int = bp.get("bank_total", 1)
            var next_idx: int = (idx % total) + 1
            _next_btn.btn_text = _bank_next_label(bp, next_idx)
        else:
            _next_btn.visible = false



func _maybe_show_stats_label() -> void :
    var beat: float = _level_config.get("beat_percent", -1.0)
    if beat < 0.0:
        return
    var elapsed: int = _level_config.get("elapsed_sec", 0)
    var m: int = elapsed / 60
    var s: int = elapsed % 60
    var top: float = snappedf(100.0 - beat, 0.1)


    _show_stats_label("⏱ %02d:%02d  ·  Top %s" % [m, s, I18nFormat.percent(top, 1)])



func _maybe_show_beat_percent_tip() -> void :
    if _beat_percent_label == null:
        return
    var text: String = _win_text.get("body", "")
    _beat_percent_label.visible = not text.is_empty()
    if not text.is_empty():
        _beat_percent_label.text = text

func _show_stats_label(text: String) -> void :
    var lbl: = Label.new()
    lbl.text = text
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.add_theme_font_size_override("font_size", 42)
    lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
    lbl.modulate.a = 0.0
    lbl.size = Vector2(_next_btn.size.x, 70.0)
    lbl.position = Vector2(_next_btn.position.x, _next_btn.position.y - 100.0)
    _next_btn.get_parent().add_child(lbl)
    var start_y: float = lbl.position.y
    var tw: = lbl.create_tween()
    tw.tween_interval(0.6)
    tw.set_parallel(true)
    tw.tween_property(lbl, "modulate:a", 1.0, 0.4)
    tw.tween_property(lbl, "position:y", start_y - 10.0, 0.4).set_ease(Tween.EASE_OUT)



func _on_next_btn_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.LEVEL_PLAY, self)
    if _level_config.get("is_daily", false):
        UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})
        return
    var lv: int = _level_config.get("level", 0)
    if lv > 0:
        UIManager.show_ui(UiName.GAME, {"level_index": lv + 1})
        return
    var bp: Dictionary = _level_config.get("bank_params", {})
    if bp.is_empty():
        UIManager.show_ui(UiName.GAME, {"level_index": 1})
        return
    var idx: int = bp.get("bank_index", 1)
    var total: int = bp.get("bank_total", 1)
    var next_idx: int = (idx % total) + 1
    _play_bank_level(bp, next_idx, total)


func _bank_next_label(bp: Dictionary, next_idx: int) -> String:
    if bp.get("bank_sp", false):
        var sp_levels: Array = BankData.get_sp_levels()
        if next_idx - 1 < sp_levels.size():
            var e: Dictionary = sp_levels[next_idx - 1]
            var sz: int = e.get("size", 9)
            return "SP  %d×%d  #%d" % [sz, sz, next_idx]
    elif bp.get("bank_lk", false):
        var lk_levels: Array = BankData.get_lk_modified_levels() if bp.get("bank_lk_modified", false) else BankData.get_lk_levels()
        if next_idx - 1 < lk_levels.size():
            var e: Dictionary = lk_levels[next_idx - 1]
            var sz: int = int(e.get("size", 8))
            var rank: int = int(e.get("maxR", 1))
            return "%d×%d  R%d  #%d" % [sz, sz, rank, next_idx]
    elif bp.get("bank_lk_style", false):
        var sz: int = bp.get("bank_size", 7)
        var rank: int = bp.get("bank_rank", 1)
        return "%d×%d  R%d  #%d" % [sz, sz, rank, next_idx]
    else:
        var sz: int = bp.get("bank_size", 7)
        var rank: int = bp.get("bank_rank", 1)
        return "%d×%d  R%d  #%d" % [sz, sz, rank, next_idx]
    return "#%d" % next_idx


func _play_bank_level(bp: Dictionary, next_idx: int, total: int) -> void :
    if bp.get("bank_sp", false):
        var levels: Array = BankData.get_sp_levels()
        if next_idx - 1 >= levels.size():
            return
        var entry: Dictionary = levels[next_idx - 1]
        UIManager.show_ui(UiName.GAME, {
            "bank_mode": true, 
            "bank_size": entry.get("size", 9), 
            "bank_rank": entry.get("r", 1), 
            "bank_index": next_idx, 
            "bank_total": total, 
            "prebuilt_regions": entry.get("regionMap", []), 
            "prebuilt_solution": entry.get("solution", []), 
            "level_seed": entry.get("id", 0), 
            "r1_steps": entry.get("r1", 0), 
            "r2_steps": entry.get("r2", 0), 
            "r3_steps": entry.get("r3", 0), 
            "r4_steps": entry.get("r4", 0), 
            "r5_steps": entry.get("r5", 0), 
            "bank_sp": true, 
            "custom_color_map": entry.get("colorMap", []), 
        })
    elif bp.get("bank_lk", false):
        var is_lk_modified: bool = bp.get("bank_lk_modified", false)
        var levels: Array = BankData.get_lk_modified_levels() if is_lk_modified else BankData.get_lk_levels()
        if next_idx - 1 >= levels.size():
            return
        var entry: Dictionary = levels[next_idx - 1]
        UIManager.show_ui(UiName.GAME, {
            "bank_mode": true, 
            "bank_lk": true, 
            "bank_lk_modified": is_lk_modified, 
            "bank_size": int(entry.get("size", 8)), 
            "bank_rank": int(entry.get("maxR", 1)), 
            "bank_index": next_idx, 
            "bank_total": total, 
            "prebuilt_regions": entry.get("regionMap", []), 
            "prebuilt_solution": entry.get("solution", []), 
            "level_seed": entry.get("id", 0), 
        })
    elif bp.get("bank_lk_style", false):
        var sz: int = bp.get("bank_size", 7)
        var rank: int = bp.get("bank_rank", 1)
        var is_tier_h: bool = bp.get("bank_tier_h", false)
        var levels: Array = BankData.get_lk_style_levels_by_tier(sz, rank, "H") if is_tier_h\
else BankData.get_lk_style_levels(sz, rank)
        if next_idx - 1 >= levels.size():
            return
        var entry: Dictionary = levels[next_idx - 1]
        UIManager.show_ui(UiName.GAME, {
            "bank_mode": true, 
            "bank_size": sz, 
            "bank_rank": rank, 
            "bank_index": next_idx, 
            "bank_total": total, 
            "prebuilt_regions": entry.get("regionMap", []), 
            "prebuilt_solution": entry.get("solution", []), 
            "level_seed": entry.get("seed", 0), 
            "r1_steps": entry.get("r1", 0), 
            "r2_steps": entry.get("r2", 0), 
            "r3_steps": entry.get("r3", 0), 
            "r4_steps": entry.get("r4", 0), 
            "r5_steps": entry.get("r5", 0), 
            "bank_lk_style": true, 
            "bank_tier_h": is_tier_h, 
        })
    elif bp.get("bank_gc", false):
        var sz: int = bp.get("bank_size", 7)
        var rank: int = bp.get("bank_rank", 1)
        var bank_tier: String = bp.get("bank_tier", "")
        var levels: Array = BankData.get_gc_levels_by_tier(sz, rank, bank_tier)\
if (bank_tier == "H" or bank_tier == "N")\
else BankData.get_gc_levels(sz, rank)
        if next_idx - 1 >= levels.size():
            return
        var entry: Dictionary = levels[next_idx - 1]
        UIManager.show_ui(UiName.GAME, {
            "bank_mode": true, 
            "bank_size": sz, 
            "bank_rank": rank, 
            "bank_index": next_idx, 
            "bank_total": total, 
            "prebuilt_regions": entry.get("regionMap", []), 
            "prebuilt_solution": entry.get("solution", []), 
            "level_seed": entry.get("seed", 0), 
            "r1_steps": entry.get("r1", 0), 
            "r2_steps": entry.get("r2", 0), 
            "r3_steps": entry.get("r3", 0), 
            "r4_steps": entry.get("r4", 0), 
            "r5_steps": entry.get("r5", 0), 
            "bank_gc": true, 
            "bank_tier": bank_tier, 
            "bank_tier_h": bank_tier == "H", 
        })
    else:
        var sz: int = bp.get("bank_size", 7)
        var rank: int = bp.get("bank_rank", 1)
        var is_tier_h: bool = bp.get("bank_tier_h", false)
        var levels: Array = BankData.get_levels_by_tier(sz, rank, "H") if is_tier_h\
else BankData.get_levels(sz, rank)
        if next_idx - 1 >= levels.size():
            return
        var entry: Dictionary = levels[next_idx - 1]
        UIManager.show_ui(UiName.GAME, {
            "bank_mode": true, 
            "bank_size": sz, 
            "bank_rank": rank, 
            "bank_index": next_idx, 
            "bank_total": total, 
            "prebuilt_regions": entry.get("regionMap", []), 
            "prebuilt_solution": entry.get("solution", []), 
            "level_seed": entry.get("seed", 0), 
            "r1_steps": entry.get("r1", 0), 
            "r2_steps": entry.get("r2", 0), 
            "r3_steps": entry.get("r3", 0), 
            "r4_steps": entry.get("r4", 0), 
            "r5_steps": entry.get("r5", 0), 
            "bank_tier_h": is_tier_h, 
        })


func get_scr_name() -> String:
    return Tracker.Scr.NORMAL_GAME_SUCCESS
