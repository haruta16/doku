@tool
extends Control

signal tag_pressed

@export var bg_color: Color = Color(0.945, 0.576, 0.125, 1):
    set(value):
        bg_color = value
        _apply_bg_color()

@export var shadow_color: Color = Color(0.945, 0.576, 0.125, 0.7):
    set(value):
        shadow_color = value
        _apply_shadow_color()

@export var btn_text: String = "":
    set(value):
        btn_text = value
        _apply_text()

@export var text_color: Color = Color(1, 1, 1, 1):
    set(value):
        text_color = value
        _apply_text_color()

@export var show_difficult: bool = true:
    set(value):
        show_difficult = value
        _apply_show_difficult()

@export var show_shadow: bool = true:
    set(value):
        show_shadow = value
        _apply_show_shadow()

@onready var _anim: AnimationPlayer = $AnimationPlayer

func _ready() -> void :
    _duplicate_styles()
    _apply_bg_color()
    _apply_shadow_color()
    _apply_text()
    _apply_text_color()
    _apply_show_difficult()
    _apply_show_shadow()
    if not Engine.is_editor_hint():
        $Root / Bg.pressed.connect(_on_bg_pressed)
        $Root / Bg.button_down.connect(_on_bg_button_down)
        $Root / Bg.button_up.connect(_on_bg_button_up)

func _notification(what: int) -> void :
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _apply_text()

func _on_bg_pressed() -> void :
    tag_pressed.emit()

func _on_bg_button_down() -> void :
    _anim.play_section_with_markers("GenericButton", &"", &"PressAndHold")

func _on_bg_button_up() -> void :
    _anim.play_section_with_markers("GenericButton", &"PressAndHold", &"")

func _duplicate_styles() -> void :
    var bg: Button = $Root / Bg
    for state: String in ["normal", "hover", "pressed"]:
        var style: = bg.get_theme_stylebox(state) as StyleBoxFlat
        if style:
            bg.add_theme_stylebox_override(state, style.duplicate())

func _apply_bg_color() -> void :
    if not is_node_ready():
        return
    var bg: Button = $Root / Bg
    for state: String in ["normal", "hover", "pressed"]:
        var style: = bg.get_theme_stylebox(state) as StyleBoxFlat
        if style:
            style.bg_color = bg_color

func _apply_shadow_color() -> void :
    if not is_node_ready():
        return
    var shadow: NinePatchRect = $Root / Shadow
    shadow.self_modulate = shadow_color

const _BASE_FONT_SIZE: int = 80
const _MIN_FONT_SIZE: int = 40

func _apply_text() -> void :
    if not is_node_ready():
        return
    var label: Label = $Root / Text
    label.text = btn_text
    var fs: int = _BASE_FONT_SIZE
    label.add_theme_font_size_override("font_size", fs)
    while fs > _MIN_FONT_SIZE and label.get_minimum_size().x > label.size.x:
        fs -= 4
        label.add_theme_font_size_override("font_size", fs)

func _apply_text_color() -> void :
    if not is_node_ready():
        return
    $Root / Text.add_theme_color_override("font_color", text_color)

func _apply_show_difficult() -> void :
    if not is_node_ready():
        return
    $Root / Diffcult.visible = show_difficult

func _apply_show_shadow() -> void :
    if not is_node_ready():
        return
    $Root / Shadow.visible = show_shadow
