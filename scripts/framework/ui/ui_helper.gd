## 按钮按压反馈辅助：绑定按下与释放缩放，统一支点和中断动画的处理。
class_name UIHelper
extends RefCounted

# ---- 动画参数（倍率 / 秒） ----
const PRESS_SCALE_RATIO: float = 0.9 # 按下时缩到基准的 90%
const RELEASE_OVERSHOOT_RATIO: float = 1.03 # 松手回弹时过冲到 103%
const PRESS_DURATION: float = 0.0667 # 按下收缩时长 0.0667 秒（约 4 帧 @60fps）
const RELEASE_OVERSHOOT_DURATION: float = 0.167 # 回弹到过冲值的时长 0.167 秒
const RELEASE_RECOVER_DURATION: float = 0.2 # 从过冲值回到基准的时长 0.2 秒
const _PRESS_SCALE_TWEEN_META: StringName = &"_ui_press_scale_tween" # 存 tween 的 meta 键名：保证一个节点只有一个按压 tween


## 按下反馈：缩到 base_scale 的 0.9 倍；先杀掉该节点未播完的旧 tween
static func play_press_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void:
	if not is_instance_valid(node):
		return
	_ensure_center_pivot(node)
	_kill_press_scale_tween(node)
	var t := node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", base_scale * PRESS_SCALE_RATIO, PRESS_DURATION)
	node.set_meta(_PRESS_SCALE_TWEEN_META, t)


## 松手反馈：两段动画——先过冲到 1.03 倍，再落回 base_scale
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


static func reset_press_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void:
	if not is_instance_valid(node):
		return
	_kill_press_scale_tween(node)
	if node is Control:
		(node as Control).scale = base_scale
	elif node is Node2D:
		(node as Node2D).scale = base_scale


## 给按钮接上按下/松手反馈；UIFrameWindow 也提供同名转发方法给页面用
static func bind_press_release_scale(button: BaseButton, base_scale: Vector2 = Vector2.ONE) -> void:
	if not is_instance_valid(button):
		return
	_ensure_center_pivot(button)
	button.button_down.connect(func() -> void: UIHelper.play_press_scale(button, base_scale))
	button.button_up.connect(func() -> void: UIHelper.play_release_scale(button, base_scale))


## 把轴心挪到中心，否则缩放会从左上角开始
static func _ensure_center_pivot(node: CanvasItem) -> void:
	if node is Control:
		(node as Control).pivot_offset_ratio = Vector2(0.5, 0.5)


static func _kill_press_scale_tween(node: CanvasItem) -> void:
	if not node.has_meta(_PRESS_SCALE_TWEEN_META):
		return
	var tween: Tween = node.get_meta(_PRESS_SCALE_TWEEN_META)
	if tween:
		tween.kill()
	node.remove_meta(_PRESS_SCALE_TWEEN_META)
