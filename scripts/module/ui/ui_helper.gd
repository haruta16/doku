class_name UIHelper
extends RefCounted

const PRESS_SCALE_RATIO: float = 0.9
const RELEASE_OVERSHOOT_RATIO: float = 1.03
const PRESS_DURATION: float = 0.0667
const RELEASE_OVERSHOOT_DURATION: float = 0.167
const RELEASE_RECOVER_DURATION: float = 0.2
const _PRESS_SCALE_TWEEN_META: StringName = &"_ui_press_scale_tween"


static func play_press_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void:
	if not is_instance_valid(node):
		return
	_ensure_center_pivot(node)
	_kill_press_scale_tween(node)
	var t := node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", base_scale * PRESS_SCALE_RATIO, PRESS_DURATION)
	node.set_meta(_PRESS_SCALE_TWEEN_META, t)


static func play_release_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void:
	if not is_instance_valid(node):
		return
	_ensure_center_pivot(node)
	_kill_press_scale_tween(node)
	var t := node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(
		node, "scale", base_scale * RELEASE_OVERSHOOT_RATIO, RELEASE_OVERSHOOT_DURATION
	)
	t.tween_property(node, "scale", base_scale, RELEASE_RECOVER_DURATION)
	node.set_meta(_PRESS_SCALE_TWEEN_META, t)


static func bind_press_release_scale(button: BaseButton, base_scale: Vector2 = Vector2.ONE) -> void:
	if not is_instance_valid(button):
		return
	_ensure_center_pivot(button)
	button.button_down.connect(func() -> void: UIHelper.play_press_scale(button, base_scale))
	button.button_up.connect(func() -> void: UIHelper.play_release_scale(button, base_scale))


static func _ensure_center_pivot(node: CanvasItem) -> void:
	if node is Control:
		(node as Control).pivot_offset_ratio = Vector2(0.5, 0.5)


static func _kill_press_scale_tween(node: CanvasItem) -> void:
	if not node.has_meta(_PRESS_SCALE_TWEEN_META):
		return
	var t: Tween = node.get_meta(_PRESS_SCALE_TWEEN_META)
	if t and t.is_valid():
		t.kill()
