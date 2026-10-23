## 观察力鼓励文字：播放反馈并按实际内容宽度居中，向外提供布局边界。
class_name GoodEyeText
extends Control

const DISPLAY_SCALE: float = 0.5

const _INK_TOP_PX_EN: float = 4.0
const _INK_TOP_PX_JP: float = 2.0

const _INK_SIDE_PX_EN: Vector2 = Vector2(12.0, 12.0)
const _INK_SIDE_PX_JP: Vector2 = Vector2(8.0, 8.0)

@onready var _text_en: TextureRect = $TextEn
@onready var _text_jp: TextureRect = $TextJp
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _ink_top_inset: float = 0.0

var _ink_side_inset: Vector2 = Vector2.ZERO


func play(use_japanese: bool) -> void:
	var picked: TextureRect = _text_jp if use_japanese else _text_en
	_text_en.visible = false
	_text_jp.visible = false
	if picked.texture == null:
		push_error("GoodEyeText: %s 未绑定贴图" % picked.name)
		return
	picked.visible = true
	var display_size: Vector2 = picked.texture.get_size() * DISPLAY_SCALE
	_fit_centered(picked, display_size)
	_ink_top_inset = (_INK_TOP_PX_JP if use_japanese else _INK_TOP_PX_EN) * DISPLAY_SCALE
	_ink_side_inset = (_INK_SIDE_PX_JP if use_japanese else _INK_SIDE_PX_EN) * DISPLAY_SCALE

	custom_minimum_size = display_size
	size = display_size

	pivot_offset = display_size * 0.5
	if not _anim.has_animation("Appear"):
		push_error("GoodEyeText: 缺 Appear 动画")
		return
	_anim.play("Appear")

	_anim.animation_finished.connect(_on_appear_finished, CONNECT_ONE_SHOT)

	_anim.advance(0.0)


func _on_appear_finished(_anim_name: StringName) -> void:
	queue_free()


func _fit_centered(content: Control, display_size: Vector2) -> void:
	content.offset_left = -display_size.x * 0.5
	content.offset_top = -display_size.y * 0.5
	content.offset_right = display_size.x * 0.5
	content.offset_bottom = display_size.y * 0.5


func get_content_width() -> float:
	return size.x


func get_content_top_inset() -> float:
	return _ink_top_inset


func get_content_side_inset() -> Vector2:
	return _ink_side_inset
