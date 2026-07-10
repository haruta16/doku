class_name BaseGameToast
extends CanvasLayer












const DISAPPEAR_MARKER: StringName = &"Disappear"


const DISAPPEAR_MARKER_FALLBACK: StringName = &"Mark"
const HOLD_AT_DISAPPEAR_SEC: float = 1.4

@onready var _root: Control = $Root
@onready var _card: Control = $Root / Card
@onready var _anim_player: AnimationPlayer = $AnimationPlayer


const _CARD_NAMES: Array[String] = ["Card2", "Card4", "Card5", "Card6"]


var _label: RichTextLabel = null





var _active_appear_anim: StringName = &""


@export var sibling_toast: CanvasLayer


var _seq_token: int = 0


func _ready() -> void :
    _anim_player.animation_finished.connect(_on_anim_finished)

    _root.gui_input.connect(_on_root_gui_input)
    _on_ready_extra()






func _appear_anim() -> StringName:
    return &""




func _resolve_appear_anim() -> StringName:
    if _active_appear_anim != &"" and _anim_player != null and _anim_player.has_animation(_active_appear_anim):
        return _active_appear_anim
    return _appear_anim()




func _disappear_marker_time(anim: Animation) -> float:
    if anim == null:
        return -1.0
    if anim.has_marker(DISAPPEAR_MARKER):
        return anim.get_marker_time(DISAPPEAR_MARKER)
    if anim.has_marker(DISAPPEAR_MARKER_FALLBACK):
        return anim.get_marker_time(DISAPPEAR_MARKER_FALLBACK)
    return -1.0



func _dlg_name() -> String:
    return ""




func _label_subpath() -> String:
    return ""



func _apply_text(params: Dictionary) -> void :
    var text_key: String = params.get("text_key", "GAME_TOAST_FIRST_TRY")
    var pct_str: String = params.get("pct_str", "0.0%")
    _label.text = tr(text_key) % pct_str



func _on_ready_extra() -> void :
    pass







func set_card_position(top_left: Vector2) -> void :
    if _card != null:
        _card.position = top_left



func set_card_center(center: Vector2) -> void :
    if _card != null:
        _card.position = center - _card.size * 0.5





func show_toast(params: Dictionary = {}) -> void :

    if sibling_toast != null and is_instance_valid(sibling_toast) and sibling_toast.visible:
        if sibling_toast.has_method("hide_toast"):
            sibling_toast.hide_toast()
    visible = true


    _select_variant_card()
    _apply_text(params)




    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE if _is_click_through_group() else Control.MOUSE_FILTER_STOP
    _seq_token += 1
    Tracker.track_dlg_show(_dlg_name())
    _play_entry_anim(_seq_token)




func _is_click_through_group() -> bool:
    return ABTestManager.normal_start_toast.value() in [3, 5, 6]





func _select_variant_card() -> void :
    var target: String = ABTestManager.normal_start_toast.get_variant_card()
    for card_name in _CARD_NAMES:
        var c: Control = _card.get_node_or_null(card_name) as Control
        if c != null:
            c.visible = (card_name == target)

    _label = _card.get_node_or_null("%s/%s" % [target, _label_subpath()]) as RichTextLabel


    if _anim_player != null and _anim_player.has_animation(target):
        _active_appear_anim = StringName(target)



        _card.scale = Vector2.ONE
    else:
        _active_appear_anim = &""



func hide_toast() -> void :
    if not visible:
        return
    visible = false
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _seq_token += 1
    _anim_player.stop()
    Tracker.notify_dlg_closed(_dlg_name())




func _on_anim_finished(anim_name: StringName) -> void :
    if anim_name == _resolve_appear_anim():
        _root.mouse_filter = Control.MOUSE_FILTER_IGNORE

        if visible:
            visible = false
            Tracker.notify_dlg_closed(_dlg_name())




func _on_root_gui_input(event: InputEvent) -> void :
    if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        _skip_to_disappear()
        _root.accept_event()




func _input(event: InputEvent) -> void :
    if not visible or not _is_click_through_group():
        return
    var pressed: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)\
or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
    if pressed:
        _skip_to_disappear()


func _skip_to_disappear() -> void :



    var appear: StringName = _resolve_appear_anim()
    if _anim_player.assigned_animation != appear:
        return
    var anim: Animation = _anim_player.get_animation(appear)
    if anim == null:
        return
    var marker_time: float = _disappear_marker_time(anim)
    var cur: float = _anim_player.current_animation_position

    if cur >= marker_time and _anim_player.is_playing():
        return
    _seq_token += 1

    if cur < marker_time:
        _anim_player.seek(marker_time, true)
    _anim_player.play(appear)



func _play_entry_anim(token: int) -> void :
    var appear: StringName = _resolve_appear_anim()
    var anim: Animation = _anim_player.get_animation(appear)
    if anim == null:
        return
    var marker_time: float = _disappear_marker_time(anim)
    if marker_time < 0.0:

        _anim_player.play(appear)
        return
    _anim_player.play(appear)
    await get_tree().create_timer(marker_time).timeout
    if token != _seq_token or not is_inside_tree() or not visible:
        return
    _anim_player.pause()
    await get_tree().create_timer(HOLD_AT_DISAPPEAR_SEC).timeout
    if token != _seq_token or not is_inside_tree() or not visible:
        return
    _anim_player.play(appear)
