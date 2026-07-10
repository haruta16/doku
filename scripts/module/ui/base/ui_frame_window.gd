class_name UIFrameWindow
extends UIBaseWindow



var _ui_name: String = ""

func get_ui_name() -> String:
    return _ui_name


@export_enum("Default:0", "Popup:100", "Notice:200", "Modal:300", "Tutorial:400", "Loading:500") var ui_layer: int = UILayerConfig.LAYER_DEFAULT
@export var is_fullscreen: bool = false
@export var show_mask: bool = false
@export var mask_opacity: float = 0.8
@export var play_open_sound: bool = false
@export var open_anim_name: String = ""
@export var close_anim_name: String = ""



func on_stack_top() -> void :
    pass

func on_stack_bottom() -> void :
    pass



func on_escape() -> bool:
    if _close_btn != null and is_instance_valid(_close_btn):
        _close_btn.emit_signal("pressed")
        return true
    if has_method("_on_back_request"):
        call("_on_back_request")
        return true
    return false



func get_scr_name() -> String:
    return ""

func get_dlg_name() -> String:
    return ""

func get_dlg_extra() -> Dictionary:
    return {}



const _DEFAULT_ANIM: StringName = &"GenericPopup"
const _DEFAULT_MARKER: StringName = &"Mark"

func _play_open_animation() -> void :
    var anim: = find_child("AnimationPlayer", true, false) as AnimationPlayer
    if anim == null:
        if not open_anim_name.is_empty():
            push_error("UIFrameWindow[%s]: open_anim_name='%s' configured but no AnimationPlayer found in subtree" % [_ui_name, open_anim_name])
        return
    if open_anim_name.is_empty():
        if anim.has_animation(_DEFAULT_ANIM):
            anim.play_section_with_markers(_DEFAULT_ANIM, &"", _DEFAULT_MARKER)
    else:
        if anim.has_animation(open_anim_name):
            anim.play(open_anim_name)
        else:
            push_error("UIFrameWindow[%s]: open_anim_name='%s' not found in AnimationPlayer" % [_ui_name, open_anim_name])

func _play_close_animation() -> void :
    if close_anim_name.is_empty():
        return
    var anim: = find_child("AnimationPlayer", true, false) as AnimationPlayer
    if anim == null:
        push_error("UIFrameWindow[%s]: close_anim_name='%s' configured but no AnimationPlayer found in subtree" % [_ui_name, close_anim_name])
        return
    if not anim.has_animation(close_anim_name):
        push_error("UIFrameWindow[%s]: close_anim_name='%s' not found in AnimationPlayer" % [_ui_name, close_anim_name])
        return
    anim.play(close_anim_name)
    await anim.animation_finished

func _abort_close_animation() -> void :
    var anim: = find_child("AnimationPlayer", true, false) as AnimationPlayer
    if anim != null and anim.is_playing():
        anim.stop(false)






func get_hide_anim_duration() -> float:


    for node in find_children("*", "AnimationPlayer", true, false):
        var anim: = node as AnimationPlayer
        if not close_anim_name.is_empty():
            if anim.has_animation(close_anim_name):
                return anim.get_animation(close_anim_name).length
        elif anim.has_animation(_DEFAULT_ANIM):
            var a: = anim.get_animation(_DEFAULT_ANIM)
            if a.has_marker(_DEFAULT_MARKER):
                return maxf(0.0, a.length - a.get_marker_time(_DEFAULT_MARKER))
    return 0.0



var _close_btn: BaseButton = null

func _do_create() -> void :
    super._do_create()
    var btn: = find_child("CloseBtn", true, false) as BaseButton
    if btn != null and _close_btn == null:
        _close_btn = btn


        if btn.pressed.get_connections().is_empty():
            btn.pressed.connect(_on_close_btn_pressed)

func _do_show(params: Dictionary = {}) -> void :
    if play_open_sound:
        SoundManager.play(SoundManager.Kind.DLG_OPEN)
    super._do_show(params)
    _play_open_animation()

func _on_close_btn_pressed() -> void :
    UIManager.hide_ui(_ui_name)
