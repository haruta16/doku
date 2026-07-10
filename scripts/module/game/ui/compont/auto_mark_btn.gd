class_name AutoMarkBtn
extends Control







signal pressed_with_state(is_marked_before: bool)

@onready var _btn_mark: Sprite2D = $BtnAutoMark
@onready var _btn_unmark: Sprite2D = $BtnAutoUnMark
@onready var _hit: Button = $Hit

var _is_marked: bool = false

func _ready() -> void :
    _apply_visual()
    _hit.pressed.connect(_on_hit_pressed)

func _on_hit_pressed() -> void :
    pressed_with_state.emit(_is_marked)


func set_marked(marked: bool) -> void :
    if _is_marked == marked:
        return
    _is_marked = marked
    _apply_visual()

func is_marked() -> bool:
    return _is_marked



func set_flip_h(flip: bool) -> void :
    if _btn_mark != null:
        _btn_mark.flip_h = flip
    if _btn_unmark != null:
        _btn_unmark.flip_h = flip

func _apply_visual() -> void :
    if _btn_mark != null:
        _btn_mark.visible = not _is_marked
    if _btn_unmark != null:
        _btn_unmark.visible = _is_marked
