class_name StreakPage
extends UIFrameWindow

















enum DisplayState{MAIN, LIT, SETTLE}

const _WEEKDAY_LABELS: Array[String] = ["WEEKDAY_SUN", "WEEKDAY_MON", "WEEKDAY_TUE", "WEEKDAY_WED", "WEEKDAY_THU", "WEEKDAY_FRI", "WEEKDAY_SAT"]
const _PARAM_STATE: String = "state"
const _SETTLE_SLOT_DELAY: float = 20.0 / 60.0
const _LIT_SLOT_DELAY: float = 62.0 / 60.0



static func open_main() -> StreakPage:
    return UIManager.show_ui(UiName.STREAK, {_PARAM_STATE: DisplayState.MAIN}) as StreakPage


static func open_lit() -> StreakPage:
    return UIManager.show_ui(UiName.STREAK, {_PARAM_STATE: DisplayState.LIT}) as StreakPage


static func open_settle() -> StreakPage:
    return UIManager.show_ui(UiName.STREAK, {_PARAM_STATE: DisplayState.SETTLE}) as StreakPage



@onready var _slots: Array[Control] = [
    $StreakContent / StreakPanel / SlotWed, 
    $StreakContent / StreakPanel / SlotThu, 
    $StreakContent / StreakPanel / SlotFri, 
    $StreakContent / StreakPanel / SlotSat, 
    $StreakContent / StreakPanel / SlotSun, 
    $StreakContent / StreakPanel / SlotMon, 
    $StreakContent / StreakPanel / SlotTue, 
]
@onready var _streak_num: Label = $StreakContent / StreakPanel / "2Txt"
@onready var _best_streak_group: Control = $StreakContent / StreakPanel / Group5
@onready var _best_label: Label = $StreakContent / StreakPanel / Group5 / BestStreak99Txt
@onready var _claim_btn: Button = $StreakContent / ClaimBtn
@onready var _back_btn: Button = $StreakContent / Top / BackBtnGroup
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _sun_btn: Button = $StreakContent / StreakPanel / IconSlot / SunImg / SunBtn

var _state: DisplayState = DisplayState.MAIN
var _lit_consumed: bool = false
var _lit_enter_done: bool = false



func on_create() -> void :


    bind_press_release_scale(_claim_btn)
    bind_press_release_scale(_back_btn)


func on_show(params: Dictionary = {}) -> void :



    var requested: int = params.get(_PARAM_STATE, DisplayState.MAIN)
    _lit_consumed = false
    _lit_enter_done = false
    _apply_state(requested)
    _play_enter_anim(requested)
    if requested == DisplayState.SETTLE:
        _run_settle_flow()






func on_escape() -> bool:
    if _state != DisplayState.MAIN:
        return false
    _on_back_pressed()
    return true





func get_scr_name() -> String:
    match _state:
        DisplayState.MAIN:
            return Tracker.Scr.STREAK
        DisplayState.SETTLE:
            return Tracker.Scr.GAME_STREAK
        _:
            return ""










func _play_enter_anim(s: int) -> void :
    var anim_name: StringName
    match s:
        DisplayState.LIT:
            anim_name = &"Appear"
        DisplayState.SETTLE:
            anim_name = &"Appear3"
        _:
            anim_name = &"Appear2" if StreakManager.can_checkin_today() else &"Appear3"
    if _anim.has_animation(anim_name):


        if _anim.has_animation(&"RESET"):
            _anim.play(&"RESET")
            _anim.advance(0.0)
        _anim.play(anim_name)



        if s == DisplayState.LIT:
            connect_managed_once(_anim.animation_finished, _on_lit_enter_anim_finished)



func _on_lit_enter_anim_finished(_finished_anim: StringName) -> void :
    _lit_enter_done = true







func _apply_state(s: int) -> void :
    _state = s
    _refresh()



func _refresh() -> void :
    _refresh_visibility()
    _refresh_data()


func _refresh_visibility() -> void :
    var is_main: bool = _state == DisplayState.MAIN
    var is_settle: bool = _state == DisplayState.SETTLE

    _back_btn.visible = is_main

    _best_streak_group.visible = is_main or is_settle
    _claim_btn.visible = is_settle

    _sun_btn.visible = _state == DisplayState.LIT


func _refresh_data() -> void :
    var data: StreakData = StreakManager.get_data()
    _streak_num.text = str(data.current_streak)
    _best_label.text = tr("DAILY_STREAK_BEST_FORMAT") % data.best_streak
    _refresh_slots()


func _refresh_slots() -> void :

    var show_chest: bool = StreakManager.has_reward()
    var slots: Array[Dictionary] = StreakManager.get_week_slots()


    var anim_idx: int = _new_checkin_index() if _state == DisplayState.SETTLE else -1
    for i: int in range(_slots.size()):
        var s: Dictionary = slots[i]
        var slot: Control = _slots[i]
        var slot_is_chest: bool = (i == _slots.size() - 1) and show_chest
        slot.weekday = _WEEKDAY_LABELS[int(s.weekday)]
        if i == anim_idx:
            slot.apply_static(false, slot_is_chest)
        else:
            slot.apply_static(bool(s.checked), slot_is_chest)



func _new_checkin_index() -> int:
    var slots: Array[Dictionary] = StreakManager.get_week_slots()
    var idx: int = -1
    for i: int in range(slots.size()):
        if bool(slots[i].checked):
            idx = i
    return idx









func _run_settle_flow(slot_delay: float = _SETTLE_SLOT_DELAY) -> void :
    var idx: int = _new_checkin_index()
    if idx < 0:
        return
    var slot: Control = _slots[idx]
    var has_award: bool = StreakManager.get_pending_show_uid() > 0
    _set_continue_enabled( not has_award)

    await get_tree().create_timer(slot_delay).timeout
    if not is_showing():
        return

    if not has_award:

        slot.play_checkin(false)
        StreakManager.consume_pending_show()
        return




    var dur: float = slot.play_checkin(true)
    await get_tree().create_timer(dur).timeout
    if not is_showing():
        return
    StreakManager.claim_reward(false)
    StreakManager.consume_pending_show()
    slot.hide_chest()
    slot.show_unchecked_dot()
    await _await_reward_closed()
    if not is_showing():
        return
    slot.play_checkin(false)
    _set_continue_enabled(true)



func _await_reward_closed() -> void :
    var reward: = UIManager.get_ui(UiName.AWARD)
    while is_instance_valid(reward) and reward.visible:
        await reward.visibility_changed



func _set_continue_enabled(enabled: bool) -> void :
    if _claim_btn:
        _claim_btn.disabled = not enabled








func _input(event: InputEvent) -> void :
    if not is_showing() or _state != DisplayState.LIT or _lit_consumed or not _lit_enter_done:
        return
    var is_press: bool = (event is InputEventScreenTouch and event.pressed)\
or (event is InputEventMouseButton and event.pressed)
    if not is_press:
        return
    _lit_consumed = true
    get_viewport().set_input_as_handled()
    _light_up_to_settle()




func _on_sun_pressed() -> void :
    if _state != DisplayState.LIT or _lit_consumed or not _lit_enter_done:
        return
    _lit_consumed = true
    _light_up_to_settle()




func _light_up_to_settle() -> void :
    if _anim.has_animation(&"LightUp"):
        _anim.play(&"LightUp")
    _apply_state(DisplayState.SETTLE)
    _run_settle_flow(_LIT_SLOT_DELAY)

    Tracker.track_scr_show(Tracker.Scr.GAME_STREAK)



func _on_back_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.BACK, self)
    UIManager.hide_ui(UiName.STREAK)


func _on_continue_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.CONTINUE, self)
    VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
    UIManager.hide_ui(UiName.STREAK)
