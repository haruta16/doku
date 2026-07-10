class_name RuleInfoBarV4
extends Control

@onready var _control: Control = $Control
@onready var _arrow: TextureRect = $Control / Arrow
@onready var _hit: Button = $Control / Hit

var _collapsed: bool = false
var _tween: Tween


var _interactive: bool = true

func _ready() -> void :
    _hit.pressed.connect(_on_hit_pressed)
    apply_persisted_state.call_deferred()


func set_interactive(enabled: bool) -> void :
    _interactive = enabled

func apply_persisted_state() -> void :
    _collapsed = GameState.is_rule_info_bar_collapsed()
    var target_x: float = size.x - _hit.size.x if _collapsed else 0.0
    _control.position.x = target_x
    _arrow.flip_h = _collapsed

func _on_hit_pressed() -> void :
    if not _interactive:
        return
    if _tween and _tween.is_running():
        return
    if _collapsed:
        _play_expand()
    else:
        _play_collapse()

func _play_collapse() -> void :
    _collapsed = true
    GameState.set_rule_info_bar_collapsed(true)
    var target_x: float = size.x - _hit.size.x
    _tween = create_tween()
    _tween.tween_property(_control, "position:x", target_x, 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
    _tween.parallel().tween_callback(_flip_arrow_collapsed).set_delay(0.28)

func _play_expand() -> void :
    _collapsed = false
    GameState.set_rule_info_bar_collapsed(false)
    _tween = create_tween()
    _tween.tween_property(_control, "position:x", -10.0, 0.25).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
    _tween.tween_callback(_flip_arrow_expanded)
    _tween.tween_property(_control, "position:x", 0.0, 0.1).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

func _flip_arrow_collapsed() -> void :
    _arrow.flip_h = true

func _flip_arrow_expanded() -> void :
    _arrow.flip_h = false
