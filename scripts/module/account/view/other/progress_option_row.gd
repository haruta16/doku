## 本地或云端进度选项行；显示快照并维护选中外观，由父页面决定最终采用哪一项。

extends Button

const KIND_LOCAL: String = "local"

const KIND_CLOUD: String = "cloud"

const _BG_COLOR: Color = Color(1.0, 0.9384899, 0.8605769, 1.0)

const _BORDER_COLOR: Color = Color(0.94509804, 0.5764706, 0.1254902, 1.0)

const _BORDER_WIDTH: int = 6

const _CORNER_RADIUS: int = 40

@export var tex_local: Texture2D

@export var tex_cloud: Texture2D

@onready var _bg: Panel = $Bg

@onready var _border: Panel = $Border

@onready var _icon: TextureRect = $Icon

@onready var _title: Label = $TitleTxt

@onready var _level: Label = $LevelTxt

@onready var _items: Label = $ItemsTxt

@onready var _check: Control = $CheckMark

var _kind: String = KIND_LOCAL

var _selected: bool = false


func _ready() -> void:
	UIHelper.bind_press_release_scale(self)
	_apply_selected_style()


func setup(kind: String, title_text: String, level_text: String, items_text: String) -> void:
	_kind = kind
	_icon.texture = tex_cloud if kind == KIND_CLOUD else tex_local
	_title.text = title_text
	_level.text = level_text
	_items.text = items_text


func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	_apply_selected_style()


func is_selected() -> bool:
	return _selected


func get_kind() -> String:
	return _kind


func _apply_selected_style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = _BG_COLOR
	box.corner_radius_top_left = _CORNER_RADIUS
	box.corner_radius_top_right = _CORNER_RADIUS
	box.corner_radius_bottom_right = _CORNER_RADIUS
	box.corner_radius_bottom_left = _CORNER_RADIUS
	_bg.add_theme_stylebox_override(&"panel", box)

	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.corner_radius_top_left = _CORNER_RADIUS
	border.corner_radius_top_right = _CORNER_RADIUS
	border.corner_radius_bottom_right = _CORNER_RADIUS
	border.corner_radius_bottom_left = _CORNER_RADIUS
	border.border_width_left = _BORDER_WIDTH
	border.border_width_top = _BORDER_WIDTH
	border.border_width_right = _BORDER_WIDTH
	border.border_width_bottom = _BORDER_WIDTH
	border.border_color = _BORDER_COLOR
	_border.add_theme_stylebox_override(&"panel", border)
	_border.visible = _selected
	_check.visible = _selected
