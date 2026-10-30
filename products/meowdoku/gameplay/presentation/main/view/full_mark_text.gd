## 完整标记反馈文字：根据完成条件显示或撤回文案，并提供排版所需尺寸。
class_name FullMarkText
extends Control

@onready var _perfect: TextureRect = $Perfect

@onready var _clear: TextureRect = $Clear
@onready var _perfect_jp: TextureRect = $PerfectJp
@onready var _clear_jp: TextureRect = $ClearJp
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _active_text: TextureRect = null


func play(is_perfect: bool, use_japanese: bool = false) -> void:
	_active_text = _perfect_jp if is_perfect else _clear_jp
	if not use_japanese:
		_active_text = _perfect if is_perfect else _clear
	elif _active_text.texture == null:
		push_error("FullMarkText: 日文贴图未绑定，回落普通词")
		_active_text = _perfect if is_perfect else _clear
	_perfect.visible = _active_text == _perfect
	_clear.visible = _active_text == _clear
	_perfect_jp.visible = _active_text == _perfect_jp
	_clear_jp.visible = _active_text == _clear_jp
	if _active_text.texture == null:
		push_error("FullMarkText: 文案贴图未绑定")
	if _anim.has_animation("Appear"):
		_anim.play("Appear")

		_anim.animation_finished.connect(_on_appear_finished, CONNECT_ONE_SHOT)

		_anim.advance(0.0)
	else:
		push_error("FullMarkText: 缺 Appear 动画")


func _on_appear_finished(_anim_name: StringName) -> void:
	queue_free()


const RETRACT_SEC: float = 0.1

var _retracting: bool = false


func is_perfect() -> bool:
	return _active_text == _perfect or _active_text == _perfect_jp


func is_clear() -> bool:
	return _active_text == _clear or _active_text == _clear_jp


func retract() -> void:
	if _retracting:
		return
	_retracting = true
	if _anim.animation_finished.is_connected(_on_appear_finished):
		_anim.animation_finished.disconnect(_on_appear_finished)

	_anim.stop(true)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, RETRACT_SEC)
	tween.tween_callback(queue_free)


func get_content_width() -> float:
	if _active_text != null:
		return _active_text.size.x
	return size.x


const _INK_BOTTOM_PERFECT: float = 76.0
const _INK_BOTTOM_CLEAR: float = 66.5

const _INK_BOTTOM_JAPANESE: float = 65.5

const _INK_SIDE_PX_PERFECT: Vector2 = Vector2(12.0, 12.0)
const _INK_SIDE_PX_CLEAR: Vector2 = Vector2(10.0, 10.0)
const _INK_SIDE_PX_PERFECT_JP: Vector2 = Vector2(64.0, 64.0)
const _INK_SIDE_PX_CLEAR_JP: Vector2 = Vector2(9.0, 9.0)

const _DISPLAY_SCALE: float = 0.5


func get_content_side_inset() -> Vector2:
	var node: TextureRect = _active_text if _active_text != null else _perfect
	var side_px: Vector2 = _INK_SIDE_PX_PERFECT
	if node == _clear:
		side_px = _INK_SIDE_PX_CLEAR
	elif node == _perfect_jp:
		side_px = _INK_SIDE_PX_PERFECT_JP
	elif node == _clear_jp:
		side_px = _INK_SIDE_PX_CLEAR_JP
	var box_inset: float = (size.x - node.size.x) * 0.5
	return Vector2(box_inset, box_inset) + side_px * _DISPLAY_SCALE


func get_content_bottom_offset() -> float:
	var node: TextureRect = _active_text if _active_text != null else _perfect
	var ink_bottom: float = _INK_BOTTOM_PERFECT
	if node == _clear:
		ink_bottom = _INK_BOTTOM_CLEAR
	elif node == _perfect_jp or node == _clear_jp:
		ink_bottom = _INK_BOTTOM_JAPANESE

	return size.y * node.anchor_top + node.offset_top + ink_bottom
