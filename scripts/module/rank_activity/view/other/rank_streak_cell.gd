## 连胜倍率条的单个档位格；维护标签、高亮贴图与闪烁，不修改实际连胜次数。

class_name RankStreakCell
extends Control

const FONT_HIGHLIGHT: Color = Color(1.0, 1.0, 1.0, 1.0)
const FONT_NORMAL: Color = Color(0.7529412, 0.45490196, 0.25490198, 1.0)

const _FLASH_DUR: float = 0.35

@onready var _bg: TextureRect = $Bg
@onready var _label: Label = $Label

var _tex_current: Texture2D
var _tex_normal: Texture2D
var _flash_tween: Tween

@onready var _label_base_left: float = _label.offset_left
@onready var _label_base_right: float = _label.offset_right
var _label_nudge_x: float = 0.0


func setup(
	multiplier: int, tex_current: Texture2D, tex_normal: Texture2D, label_nudge_x: float = 0.0
) -> void:
	_tex_current = tex_current
	_tex_normal = tex_normal
	_label_nudge_x = label_nudge_x
	_label.offset_left = _label_base_left + label_nudge_x
	_label.offset_right = _label_base_right + label_nudge_x

	_label.text = "x%d" % multiplier
	set_current(false)
	set_label_highlight(false)


func set_current(current: bool) -> void:
	_bg.texture = _tex_current if current else _tex_normal


func set_label_highlight(highlight: bool) -> void:
	set_label_color(FONT_HIGHLIGHT if highlight else FONT_NORMAL)


func set_label_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)


func get_label() -> Label:
	return _label


func get_current_texture() -> Texture2D:
	return _tex_current


func get_normal_texture() -> Texture2D:
	return _tex_normal


func get_label_center() -> Vector2:
	return position + size * 0.5 + Vector2(_label_nudge_x, 0.0)


func flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_label.scale = Vector2.ONE
	_flash_tween = create_tween()
	(
		_flash_tween
		. tween_property(_label, "scale", Vector2(1.25, 1.25), _FLASH_DUR * 0.5)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_flash_tween.tween_property(_label, "scale", Vector2.ONE, _FLASH_DUR * 0.5)


func stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	_label.scale = Vector2.ONE
