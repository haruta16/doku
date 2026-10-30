## 落猫鼓励文字控件：播放出现动画并暴露内容尺寸，供页面定位。
class_name CatToastText
extends Control

const DISPLAY_SCALE: float = 1.0

const INK_TOP_INSET: float = 2.0

@onready var _texture_rect: TextureRect = $Text
@onready var _anim: AnimationPlayer = $AnimationPlayer


func play(texture: Texture2D) -> void:
	if texture == null:
		push_error("CatToastText: 贴图为空(池子没配 / 场景索引越界),本次不显示")
		queue_free()
		return
	_texture_rect.texture = texture
	var display_size: Vector2 = texture.get_size() * DISPLAY_SCALE

	custom_minimum_size = display_size
	size = display_size

	pivot_offset = display_size * 0.5

	_texture_rect.offset_left = -display_size.x * 0.5
	_texture_rect.offset_top = -display_size.y * 0.5
	_texture_rect.offset_right = display_size.x * 0.5
	_texture_rect.offset_bottom = display_size.y * 0.5
	if not _anim.has_animation("Appear"):
		push_error("CatToastText: 缺 Appear 动画")
		return
	_anim.play("Appear")

	_anim.animation_finished.connect(_on_appear_finished, CONNECT_ONE_SHOT)

	_anim.advance(0.0)


func _on_appear_finished(_anim_name: StringName) -> void:
	queue_free()


func get_content_width() -> float:
	return _texture_rect.size.x


func get_content_top_inset() -> float:
	return INK_TOP_INSET * DISPLAY_SCALE
