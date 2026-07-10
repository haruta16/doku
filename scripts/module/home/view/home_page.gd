class_name HomePage
extends UIFrameWindow

@onready var _start_btn: Control = $Root / StartBtn
@onready var _daily_btn: Button = $Root / DailyBtn
@onready var _daily_bg: Button = $Root / DailyBtn / Bg
@onready var _daily_shadow: NinePatchRect = $Root / DailyBtn / Shadow
@onready var _daily_lock_icon: HBoxContainer = $Root / DailyBtn / LockIcon
@onready var _daily_lock_label: Label = $Root / DailyBtn / LockIcon / LockLabel
@onready var _daily_unlock_box: HBoxContainer = $Root / DailyBtn / UnlockBox
@onready var _daily_unlock_label: Label = $Root / DailyBtn / UnlockBox / UnlockLabel
@onready var _daily_done_tag: Panel = $Root / DailyBtn / DoneTag
@onready var _daily_done_time: Label = $Root / DailyBtn / DoneTag / DoneHBox / DoneTimeLabel
@onready var _daily_top_tag: Control = $Root / DailyBtn / TopTag
@onready var _daily_top_label: Label = $Root / DailyBtn / TopTag / TopLabel
@onready var _countdown_tag: Panel = $Root / DailyBtn / CountdownTag
@onready var _daily_paw: TextureRect = $Root / DailyBtn / UnlockBox / Paw



@export var _daily_paw_tex_lit: Texture2D
@export var _daily_paw_tex_dim: Texture2D

var _daily_sf_normal: StyleBox
var _daily_sf_pressed: StyleBox
@onready var _countdown_label: Label = $Root / DailyBtn / CountdownTag / HBox / CountdownLabel
@onready var _countdown_timer: Timer = $Root / DailyBtn / CountdownTimer
@onready var _anim: AnimationPlayer = $AnimationPlayer








const _DC_ENTRY_CELL: PackedScene = preload("res://scripts/module/daily/ui/daily_challenge_entry_cell.tscn")
const _STREAK_ENTRY_CELL: PackedScene = preload("res://scripts/module/daily_streak/ui/streak_entry_cell.tscn")


@onready var _streak_layout: Control = $Root / DailyStreakLayout
@onready var _dc_slot: Control = $Root / DailyStreakLayout / DcEntrySlot
@onready var _streak_slot: Control = $Root / DailyStreakLayout / StreakEntrySlot
@onready var _start_btn_slot: Control = $Root / DailyStreakLayout / StartBtnSlot
@onready var _logo_slot: Control = $Root / DailyStreakLayout / LogoSlot

@onready var _loge: Control = $Root / Loge
var _dc_cell = null
var _streak_cell = null


var _start_btn_orig_off_l: float = 0.0
var _start_btn_orig_off_r: float = 0.0
var _loge_orig_pos: Vector2 = Vector2.ZERO


const _START_BTN_SOLO_OFFSET_TOP: float = 366.0
const _START_BTN_SOLO_OFFSET_BOTTOM: float = 526.0

const _START_BTN_DUO_OFFSET_TOP: float = 222.0
const _START_BTN_DUO_OFFSET_BOTTOM: float = 382.0


const HOME_RATE_US_DELAY: float = 0.5

const HOME_RESTORE_DELAY: float = 0.4


static var last_restore_status: String = "尚未触发补发判定"


var _is_exiting: bool = false
var _auto_mark_switch_checked: bool = false


var _tap_diag_last_ms: int = 0
var _pending_page: String = ""
var _pending_params: Dictionary = {}
var _new_page_node: Node = null
func _ready() -> void :

    _start_btn_orig_off_l = _start_btn.offset_left
    _start_btn_orig_off_r = _start_btn.offset_right
    if _loge != null:
        _loge_orig_pos = _loge.position
    bind_press_release_scale($Root / VBoxContainer / Header / SettingsBtn)
    bind_press_release_scale($Root / DailyBtn)
    _fit_daily_btn_font()

    claim_button_sound($Root / VBoxContainer / Header / SettingsBtn)

    var grid: Sprite2D = $Background / GridFlowLoop
    var vp_w: float = get_viewport_rect().size.x
    grid.position.x = vp_w / 2.0
    if vp_w > 1080.0:
        var s: float = (vp_w / 1080.0) * 1.02
        grid.scale = Vector2(s, s)





func _write_setting_anchor() -> void :
    var gb: Control = $Root / VBoxContainer / Header / SettingsBtn
    HomeSettingAnchor.set_settingbtn_y(gb.global_position.y + gb.size.y * 0.5)


func _notification(what: int) -> void :
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _refresh_dynamic_text()
        _fit_daily_btn_font()

func _refresh_dynamic_text() -> void :
    _start_btn.btn_text = tr("GAME_LEVEL_TITLE") % GameState.get_current_level()

const _DAILY_BTN_MIN_FONT_SIZE: int = 44





func _fit_daily_btn_font() -> void :
    var display_text: String = tr("HOME_DAILY_CHALLENGE")
    var btn_w: float = _daily_btn.offset_right - _daily_btn.offset_left
    var lock_avail: float = btn_w - 56.0 - 40.0
    var lock_font: Font = _daily_lock_label.get_theme_font("font")
    var lock_fs: int = 80
    while lock_fs > _DAILY_BTN_MIN_FONT_SIZE:
        if lock_font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lock_fs).x <= lock_avail:
            break
        lock_fs -= 2
    _daily_lock_label.add_theme_font_size_override("font_size", lock_fs)

    var unlock_avail: float = btn_w - 100.0 - 20.0 - 60.0
    var unlock_font: Font = _daily_unlock_label.get_theme_font("font")
    var unlock_fs: int = 66
    while unlock_fs > _DAILY_BTN_MIN_FONT_SIZE:
        if unlock_font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, unlock_fs).x <= unlock_avail:
            break
        unlock_fs -= 2
    _daily_unlock_label.add_theme_font_size_override("font_size", unlock_fs)

func on_show(_params: Dictionary = {}) -> void :
    print("[StreakSwitch] home.on_show 被调用")






    UniKitManager.destroy_ad("banner")


    SoundManager.start_bgm()

    HelpshiftManager.request_unread()
    _is_exiting = false
    _new_page_node = null
    $Root / VBoxContainer / Header / SettingsBtn.modulate.a = 0.0

    _write_setting_anchor.call_deferred()
    $Root / StartBtn.modulate.a = 0.0
    $Root / DailyBtn.modulate.a = 0.0
    _anim.stop()
    _anim.play_section_with_markers(&"MainInterface", &"", &"disappear")
    if _daily_sf_normal == null:
        _daily_sf_normal = _daily_bg.get_theme_stylebox("normal")
        _daily_sf_pressed = _daily_sf_normal
    var lv: int = GameState.get_current_level()
    _refresh_dynamic_text()
    _start_btn.show_difficult = LevelData.is_hard_level_group_j(lv) if ABTestManager.rule_normal_rank.is_group_j() else LevelData.is_hard_level(lv)
    var hide_dc: bool = ABTestManager.no_dc.is_daily_challenge_hidden()
    _daily_btn.visible = not hide_dc
    if hide_dc:
        _start_btn.offset_top = _START_BTN_SOLO_OFFSET_TOP
        _start_btn.offset_bottom = _START_BTN_SOLO_OFFSET_BOTTOM
    else:
        _start_btn.offset_top = _START_BTN_DUO_OFFSET_TOP
        _start_btn.offset_bottom = _START_BTN_DUO_OFFSET_BOTTOM
    if not hide_dc:

        DailyEntryState.ensure_max_daily_advanced()
        _refresh_daily_btn_state()
        _fit_daily_btn_font()
        _update_countdown()
        _countdown_timer.start()


    _apply_home_layout()


    StreakManager.notify_group_dyed()


    if not await _maybe_show_streak_switch_popup():
        await _maybe_show_auto_mark_switch_popup()


    await _maybe_show_rate_us_on_home()
    await _maybe_show_pending_rewards()




func _maybe_show_streak_switch_popup() -> bool:
    var page: int = StreakManager.get_pending_switch_page()
    print("[StreakSwitch] home._maybe_show_streak_switch_popup: pending=%d" % page)
    if page <= 0:
        return false
    StreakManager.consume_pending_switch()
    var ui_name: StringName
    match page:
        1: ui_name = UiName.STREAK_SWITCH1
        2: ui_name = UiName.STREAK_SWITCH2
        3: ui_name = UiName.STREAK_SWITCH3
        _: return false



    await get_tree().create_timer(0.1).timeout
    if not visible or _is_exiting:
        return false
    var dlg: UIFrameWindow = UIManager.show_ui(ui_name)
    if dlg == null:
        return false
    while dlg.visible:
        await dlg.visibility_changed
    return true




func _maybe_show_auto_mark_switch_popup() -> void :
    if _auto_mark_switch_checked:
        return
    _auto_mark_switch_checked = true

    var stored: int = GameState.get_saved_game_auto_mark()
    if stored == -1:
        return

    var current: int = ABTestManager.find_config("game_auto_mark").peek_value()
    if stored == current:
        return

    var text_key: String = ""
    if stored in [1, 2, 4, 5] and current == 0:
        text_key = "GAME_AUTO_MARK_SWITCH_ENDED_DESC"
    elif stored in [1, 2, 3, 4] and current in [1, 2, 3, 4]:
        text_key = "GAME_AUTO_MARK_SWITCH_UPGRADED_DESC"

    if text_key.is_empty():
        return

    await get_tree().create_timer(0.1).timeout
    if not visible or _is_exiting:
        return

    var dlg: UIFrameWindow = UIManager.show_ui(UiName.AB_SWITCH_POPUP, {
        "title": "DAILY_STREAK_MAJOR_UPDATE", 
        "text": text_key, 
        "btn_text": "DAILY_STREAK_GET_IT", 
    })
    if dlg == null:
        return
    while dlg.visible:
        await dlg.visibility_changed

    GameState.set_saved_game_auto_mark(current)














func _maybe_show_pending_rewards() -> void :
    await get_tree().create_timer(HOME_RESTORE_DELAY).timeout
    if _is_exiting or not visible:
        last_restore_status = "延迟期间玩家已离开 home,放弃本次判定"
        return
    if not GameState.has_pending_rewards():
        last_restore_status = "无待补发奖励(漏奖队列为空)"
        return


    var grantable: Array = []
    for pr in GameState.get_pending_rewards():
        var r_items: Array = UniKitManager.restore_items_for_position(str(pr.get("source", "")))
        if r_items.is_empty():
            continue
        grantable.append({"entry": pr, "items": r_items})
    if grantable.is_empty():

        last_restore_status = "队列非空但无可补发道具(广告位非补发类)"
        GameState.pop_all_pending_rewards()
        return

    var now: int = int(Time.get_unix_time_from_system())
    var remaining: int = GameState.get_restore_remaining_today(now)
    if remaining <= 0:
        last_restore_status = "今日不补发(已达上限或防刷未过,今日已补发 %d 次)" % GameState.get_restored_today_count()
        return

    grantable.reverse()
    var to_grant: Array = grantable.slice(0, remaining)

    var by_kind: Dictionary = {}
    var granted_entries: Array = []
    for g in to_grant:
        for it in g.items:
            var gk: String = str(it.get("kind", ""))
            if gk == "":
                continue
            by_kind[gk] = int(by_kind.get(gk, 0)) + int(it.get("count", 0))
        granted_entries.append(g.entry)
    var rewards: Array = []
    for k in by_kind:
        rewards.append({"kind": k, "count": int(by_kind[k])})
    last_restore_status = "本批弹出 %d 次补发/%d 种道具(今日可发 %d 次, 队列可补 %d 次)" % [to_grant.size(), rewards.size(), remaining, grantable.size()]
    var page: = UIManager.show_ui(UiName.AD_REWARD_RESTORED, {"rewards": rewards})
    if page == null:
        return


    var result: = {"done": false, "collected": false, "rewards": []}
    page.collected.connect( func(rewards_collected: Array) -> void :
        result.rewards = rewards_collected
        result.collected = true
        result.done = true
    , CONNECT_ONE_SHOT)
    page.closed.connect( func() -> void :
        result.done = true
    , CONNECT_ONE_SHOT)
    while not result.done:
        await get_tree().process_frame
    if result.collected:


        GameState.add_restored_today_count(to_grant.size())

    GameState.remove_pending_rewards(granted_entries)
    UIManager.hide_ui(UiName.AD_REWARD_RESTORED)






func _maybe_show_rate_us_on_home() -> void :
    var lv: int = GameState.get_current_level()
    if not ABTestManager.rate_us_pop.is_eligible_at_home(lv):
        return
    if not GameState.has_won_since_cold_start() or GameState.has_shown_rate_us():
        return
    if not UniKitManager.is_online():
        return
    GameState.mark_rate_us_shown()
    await get_tree().create_timer(HOME_RATE_US_DELAY).timeout

    if _is_exiting or not visible:
        return

    var rate_us: = UIManager.show_ui(UiName.RATE_US)
    var data: Dictionary = await rate_us.closed
    UIManager.hide_ui(UiName.RATE_US)
    if data.get("is_submitted") and data.get("star_count", 0) > 4:

        InAppReviewManager.request_review()
    elif data.get("is_submitted") and data.get("star_count", 0) <= 4:
        var feedback: = UIManager.show_ui(UiName.FEEDBACK, {"as_dlg": true})
        await feedback.closed
        UIManager.hide_ui(UiName.FEEDBACK)

func on_hide() -> void :
    _countdown_timer.stop()
    visible = false

func _on_countdown_timer_timeout() -> void :
    _update_countdown()

func _update_countdown() -> void :


    DailyEntryState.ensure_max_daily_advanced()
    _refresh_daily_btn_state()
    _countdown_label.text = DailyEntryState.countdown_text()





func _on_back_request() -> void :
    if _is_exiting:
        return
    _request_quit_confirm()

func _request_quit_confirm() -> void :

    var setting: Node = UIManager.get_ui(UiName.SETTING)
    if setting != null and setting is CanvasItem and (setting as CanvasItem).visible:
        return
    UIManager.show_ui(UiName.CONFIRM, {"on_confirm": func(): get_tree().quit()})

func _on_settings_btn_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.SETTINGS, self)
    UIManager.show_ui(UiName.SETTING)

func _on_start_btn_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.NORMAL_PLAY, self)
    _exit_to_page("game", {"level_index": GameState.get_current_level()})

func _on_daily_btn_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)

    DailyEntryState.handle_click(self, _exit_to_page.bind("daily_game", {}))



func _exit_to_page(page_name: String, params: Dictionary) -> void :
    if _is_exiting:
        return
    _is_exiting = true
    _pending_page = page_name
    _pending_params = params
    var anim: Animation = _anim.get_animation(&"MainInterface")
    var entry_delay: float = maxf(0.0, anim.get_marker_time(&"Entry") - anim.get_marker_time(&"disappear"))
    if not _anim.animation_finished.is_connected(_on_anim_finished):
        _anim.animation_finished.connect(_on_anim_finished)
    _anim.play_section_with_markers(&"MainInterface", &"disappear", &"")
    get_tree().create_timer(entry_delay).timeout.connect(_on_entry_reached)

func _on_entry_reached() -> void :
    if _new_page_node != null or not is_inside_tree():
        return

    _new_page_node = UIManager.show_ui(_pending_page, _pending_params)
    if _new_page_node == null:
        return

    if _new_page_node is CanvasItem:
        z_index = (_new_page_node as CanvasItem).z_index + 1

func _on_anim_finished(_anim_name: StringName) -> void :
    if _anim.animation_finished.is_connected(_on_anim_finished):
        _anim.animation_finished.disconnect(_on_anim_finished)
    if _new_page_node != null:
        UIManager.hide_ui(UiName.HOME)



func _refresh_daily_btn_state() -> void :
    var s: int = DailyEntryState.compute_state()
    match s:
        DailyEntryState.State.LOCKED:

            var sf: = StyleBoxFlat.new()
            sf.bg_color = Color(0.667, 0.667, 0.667, 1)
            sf.set_corner_radius_all(200)
            _daily_bg.add_theme_stylebox_override("normal", sf)
            _daily_bg.add_theme_stylebox_override("pressed", sf)
            _daily_bg.add_theme_stylebox_override("hover", sf)
            _daily_shadow.visible = false
            _daily_lock_icon.visible = true
            _daily_unlock_box.visible = false
            _daily_done_tag.visible = false
            _daily_top_tag.visible = false
            _countdown_tag.visible = false
        DailyEntryState.State.DONE:

            var sf_n: = StyleBoxFlat.new()
            sf_n.bg_color = Color(0.576, 0.651, 0.945, 1)
            sf_n.set_corner_radius_all(200)
            sf_n.shadow_color = Color(0.576, 0.651, 0.945, 0.15)
            sf_n.shadow_size = 10
            sf_n.shadow_offset = Vector2(0, 4)
            var sf_p: = StyleBoxFlat.new()
            sf_p.bg_color = Color(0.471, 0.537, 0.78, 1)
            sf_p.set_corner_radius_all(200)
            _daily_bg.add_theme_stylebox_override("normal", sf_n)
            _daily_bg.add_theme_stylebox_override("pressed", sf_p)
            _daily_bg.add_theme_stylebox_override("hover", sf_n)
            _daily_shadow.visible = true
            _daily_lock_icon.visible = false
            _daily_unlock_box.visible = true
            _daily_done_tag.visible = true
            _daily_top_tag.visible = true
            _countdown_tag.visible = false
            _daily_done_time.text = DailyEntryState.done_time_text()
            _daily_top_label.text = DailyEntryState.done_rank_text()

            _daily_paw.visible = ABTestManager.dc_tag_ui.is_paw_enabled()
            if _daily_paw.visible:
                _daily_paw.texture = _daily_paw_tex_lit
            call_deferred("_update_top_tag_layout")
        _:

            _daily_bg.add_theme_stylebox_override("normal", _daily_sf_normal)
            _daily_bg.add_theme_stylebox_override("pressed", _daily_sf_pressed)
            _daily_bg.add_theme_stylebox_override("hover", _daily_sf_normal)
            _daily_shadow.visible = true
            _daily_lock_icon.visible = false
            _daily_unlock_box.visible = true
            _daily_done_tag.visible = false
            _daily_top_tag.visible = false
            _countdown_tag.visible = true

            _daily_paw.visible = ABTestManager.dc_tag_ui.is_paw_enabled()
            if _daily_paw.visible:
                _daily_paw.texture = _daily_paw_tex_dim






func _update_top_tag_layout() -> void :

    const DEFAULT_TAG_X: float = 619.0
    const DEFAULT_TAG_Y: float = -31.0
    const DEFAULT_TAG_W: float = 202.0
    const DEFAULT_TAG_H: float = 70.0
    const DEFAULT_LBL_W: float = 151.0
    const LBL_OFFSET_L: float = 30.0
    const LBL_OFFSET_T: float = 0.0
    var font: Font = _daily_top_label.get_theme_font("font")
    var fs: int = _daily_top_label.get_theme_font_size("font_size")
    var lbl_w_natural: float = ceilf(font.get_string_size(_daily_top_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)

    var lbl_w: float = max(lbl_w_natural, DEFAULT_LBL_W)
    var tag_w: float = 2.0 * lbl_w - 100.0

    var tag_x: float = (DEFAULT_TAG_X + DEFAULT_TAG_W) - tag_w
    _daily_top_tag.position = Vector2(tag_x, DEFAULT_TAG_Y)
    _daily_top_tag.size = Vector2(tag_w, DEFAULT_TAG_H)
    _daily_top_label.position = Vector2(LBL_OFFSET_L, LBL_OFFSET_T)
    _daily_top_label.size = Vector2(lbl_w, DEFAULT_TAG_H)




func _apply_home_layout() -> void :
    var use_l2: bool = ABTestManager.daily_streak.is_enabled()
    _streak_layout.visible = use_l2
    if not use_l2:


        _start_btn.offset_left = _start_btn_orig_off_l
        _start_btn.offset_right = _start_btn_orig_off_r
        if _loge != null:
            _loge.position = _loge_orig_pos
        return

    _daily_btn.visible = false

    _start_btn.global_position = _start_btn_slot.global_position
    _start_btn.size = _start_btn_slot.size

    if _loge != null:
        var slot_center: Vector2 = _logo_slot.global_position + _logo_slot.size * 0.5
        _loge.global_position = slot_center - _loge.size * 0.5


    if _dc_cell == null:
        _dc_cell = create_child(_DC_ENTRY_CELL, {})
        _mount_into_slot(_dc_cell, _dc_slot)
    if _streak_cell == null:
        _streak_cell = create_child(_STREAK_ENTRY_CELL, {})
        _mount_into_slot(_streak_cell, _streak_slot)
    _apply_streak_dead_layout()





func _apply_streak_dead_layout() -> void :
    var streak_dead: bool = ABTestManager.daily_streak.is_challenge_only()\
and DailyEntryState.compute_state() == DailyEntryState.State.LOCKED
    if _streak_cell != null:
        _streak_cell.visible = not streak_dead
    if _dc_cell != null:
        if streak_dead:



            (_dc_cell as Control).position.x = _streak_layout.size.x * 0.5 - _dc_slot.position.x - _dc_slot.size.x * 0.5
        else:
            (_dc_cell as Control).position.x = 0.0




func _mount_into_slot(cell: Node, slot: Control) -> void :
    var p: Node = cell.get_parent()
    if p != null:
        p.remove_child(cell)
    slot.add_child(cell)
    if cell is Control:
        (cell as Control).position = Vector2.ZERO



func get_scr_name() -> String:
    return Tracker.Scr.HOMEPAGE






func _input(event: InputEvent) -> void :
    pass














func _diag_tap(pos: Vector2) -> void :
    var hovered: Control = get_viewport().gui_get_hovered_control()
    var hovered_path: String = str(hovered.get_path()) if hovered != null else "null"
    var in_home: bool = hovered != null and (hovered == self or is_ancestor_of(hovered))
    if in_home:
        if _is_exiting:
            push_error("HomePage tap blocked by _is_exiting: hovered=%s pos=%s"\
%[hovered_path, str(pos)])
        return

    if _is_normal_home_overlay(hovered):
        return
    push_error("HomePage tap intercepted: hovered=%s pos=%s is_exiting=%s"\
%[hovered_path, str(pos), str(_is_exiting)])


func _is_normal_home_overlay(hovered: Control) -> bool:
    if hovered == null:
        return false

    var normal_ui: Array[StringName] = [
        UiName.SETTING, 
        UiName.CONFIRM, 
        UiName.RATE_US, 
        UiName.FEEDBACK, 
        UiName.AD_REWARD_RESTORED, 
        UiName.STREAK_SWITCH1, 
        UiName.STREAK_SWITCH2, 
        UiName.STREAK_SWITCH3, 
        UiName.AB_SWITCH_POPUP, 
    ]
    for ui_name in normal_ui:
        var win: UIFrameWindow = UIManager.get_ui(ui_name)
        if win != null and win.visible and (win == hovered or win.is_ancestor_of(hovered)):
            return true

    var node: Node = hovered
    while node != null:
        if node.name.to_lower().contains("cheat"):
            return true
        node = node.get_parent()
    return false
