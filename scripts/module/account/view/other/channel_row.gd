## 单个账号渠道按钮的表现层；负责渠道图标、样式和点击信号，不发起认证。

extends Button

const _STYLES: Dictionary = {
	AccountDefine.CHANNEL_FACEBOOK:
	{
		"bg": Color(0.09803922, 0.46666667, 0.94509804, 1.0),
		"fg": Color(1.0, 1.0, 1.0, 1.0),
		"border": false,
	},
	AccountDefine.CHANNEL_GOOGLE:
	{
		"bg": Color(1.0, 1.0, 1.0, 1.0),
		"fg": Color(0.12156863, 0.12156863, 0.12156863, 1.0),
		"border": true,
	},
	AccountDefine.CHANNEL_APPLE:
	{
		"bg": Color(0.0, 0.0, 0.0, 1.0),
		"fg": Color(1.0, 1.0, 1.0, 1.0),
		"border": false,
	},
}

const _STYLE_NEUTRAL: Dictionary = {
	"bg": Color(1.0, 1.0, 1.0, 1.0),
	"fg": Color(0.12156863, 0.12156863, 0.12156863, 1.0),
	"border": true,
}

const _BORDER_COLOR: Color = Color(0.45490196, 0.46666667, 0.45882353, 1.0)

const _BORDER_WIDTH: int = 4

const _CORNER_RADIUS: int = 200

const _ROW_W: float = 750.0

const _LABEL_L: float = 135.0

const _LABEL_R: float = 705.0

const _SHADOW_SIZE: int = 8

const _SHADOW_ALPHA: float = 0.18

@export var tex_facebook: Texture2D

@export var tex_google: Texture2D

@export var tex_apple: Texture2D

@onready var _bg: Panel = $Bg

@onready var _icon: TextureRect = $Icon

@onready var _label: Label = $LabelTxt


func _ready() -> void:
	UIHelper.bind_press_release_scale(self)


func setup(channel: String, label_text: String, center_in_button: bool = false) -> void:
	var style: Dictionary = _STYLES.get(channel, _STYLE_NEUTRAL)
	_apply_style(style)
	_icon.texture = _texture_of(channel)
	_label.text = label_text
	_label.offset_left = 0.0 if center_in_button else _LABEL_L
	_label.offset_right = _ROW_W if center_in_button else _LABEL_R


func _texture_of(channel: String) -> Texture2D:
	match channel:
		AccountDefine.CHANNEL_FACEBOOK:
			return tex_facebook
		AccountDefine.CHANNEL_GOOGLE:
			return tex_google
		AccountDefine.CHANNEL_APPLE:
			return tex_apple
	return null


func _apply_style(style: Dictionary) -> void:
	var box := StyleBoxFlat.new()
	var bg: Color = style["bg"]
	box.bg_color = bg
	box.corner_radius_top_left = _CORNER_RADIUS
	box.corner_radius_top_right = _CORNER_RADIUS
	box.corner_radius_bottom_right = _CORNER_RADIUS
	box.corner_radius_bottom_left = _CORNER_RADIUS
	if style["border"]:
		box.border_width_left = _BORDER_WIDTH
		box.border_width_top = _BORDER_WIDTH
		box.border_width_right = _BORDER_WIDTH
		box.border_width_bottom = _BORDER_WIDTH
		box.border_color = _BORDER_COLOR
	box.shadow_size = _SHADOW_SIZE
	box.shadow_color = Color(bg.r * 0.6, bg.g * 0.6, bg.b * 0.6, _SHADOW_ALPHA)
	_bg.add_theme_stylebox_override(&"panel", box)
	_label.add_theme_color_override(&"font_color", style["fg"])
