class_name LanguageOption
extends Button

const _C_SELECTED_BG: Color = Color(0.2784314, 0.7019608, 0.3419608, 1)
const _C_NORMAL_BG: Color = Color(0.9764706, 0.9254902, 0.88235295, 1)
const _C_SELECTED_TEXT: Color = Color(1, 1, 1, 1)
const _C_NORMAL_TEXT: Color = Color(0.5769231, 0.3522559, 0.3522559, 1)
const _C_SELECTED_SUB: Color = Color(0.5686275, 0.81960785, 0.6039216, 1)
const _C_NORMAL_SUB: Color = Color(0.8156863, 0.69803923, 0.67058825, 1)

@onready var _native_label: Label = $VBox/NativeLabel
@onready var _sub_label: Label = $VBox/SubLabel
@onready var _check_mark: Control = $CheckMark


func _ready() -> void:
	_sub_label.visible = true
	_check_mark.visible = false


func setup(native_text: String, sub_text: String) -> void:
	_native_label.text = native_text
	_sub_label.text = sub_text


func set_selected(selected: bool) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = _C_SELECTED_BG if selected else _C_NORMAL_BG
		style.set_corner_radius_all(30)
		add_theme_stylebox_override(state, style)
	_native_label.add_theme_color_override(
		"font_color", _C_SELECTED_TEXT if selected else _C_NORMAL_TEXT
	)
	_sub_label.add_theme_color_override(
		"font_color", _C_SELECTED_SUB if selected else _C_NORMAL_SUB
	)
	_check_mark.visible = selected
