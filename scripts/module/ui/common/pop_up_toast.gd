class_name PopUpToast
extends Control















@onready var _label: Label = $Panel / Label
@onready var _anim: AnimationPlayer = $AnimationPlayer

const _ANIM_NAME: StringName = &"Appear"
const _MARKER_NAME: StringName = &"Mark"

enum State{IDLE, APPEARING, AT_MARK, DISAPPEARING}

var _state: int = State.IDLE
var _mark_time: float = 0.0


signal appeared

signal dismissed

func _ready() -> void :
    visible = false
    var anim: Animation = _anim.get_animation(_ANIM_NAME)
    if anim != null and anim.has_marker(_MARKER_NAME):
        _mark_time = anim.get_marker_time(_MARKER_NAME)
    else:

        _mark_time = (anim.length * 0.5) if anim != null else 0.0
        push_warning("[PopUpToast] 缺少 marker '%s',_mark_time fallback=%.3f" % [str(_MARKER_NAME), _mark_time])
    _anim.animation_finished.connect(_on_anim_finished)
    set_process(false)


func set_text(msg: String) -> void :
    _label.text = msg



func pop_up() -> void :
    visible = true
    _state = State.APPEARING
    _anim.stop()
    _anim.play(_ANIM_NAME)
    set_process(true)



func dismiss() -> void :
    if _state == State.IDLE or _state == State.DISAPPEARING:
        return
    _state = State.DISAPPEARING
    set_process(false)


    if _anim.current_animation != _ANIM_NAME:
        _anim.play(_ANIM_NAME)
    _anim.seek(_mark_time, true)
    _anim.play(_ANIM_NAME)

func _process(_delta: float) -> void :
    if _state != State.APPEARING:
        return
    if _anim.current_animation == _ANIM_NAME and _anim.current_animation_position >= _mark_time:
        _anim.pause()
        _anim.seek(_mark_time, true)
        _state = State.AT_MARK
        set_process(false)
        appeared.emit()

func _on_anim_finished(anim_name: StringName) -> void :
    if anim_name != _ANIM_NAME:
        return
    if _state != State.DISAPPEARING:
        return
    _state = State.IDLE
    visible = false
    dismissed.emit()
