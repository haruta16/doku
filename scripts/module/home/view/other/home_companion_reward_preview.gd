## 陪伴猫奖励预览：按奖励类型刷新图文与翻译，统一显隐状态。
extends Control

@export var avatar: Control
@export var trial_costume: Control
@export var mouse: Control
@export var permanent_costume: Control
@export var frame: Control
@export var trial_label: Label

const _PIVOT: Vector2 = Vector2(298.5, 165.0)

const _APPEAR_STEPS: Array = [
	[0.0, 1.05, 0.1, Vector4(0.0, 0.0, 0.667, 1.0)],
	[1.05, 1.0, 0.167, Vector4(0.4, 0.0, 0.6, 1.0)],
]
const _DISAPPEAR_STEPS: Array = [
	[1.0, 1.05, 0.067, Vector4(0.0, 0.0, 0.5, 1.0)],
	[1.05, 0.0, 0.133, Vector4(0.5, 0.0, 1.0, 1.0)],
]

var _shown: bool = false
var _tween: Tween


func _ready() -> void:
	pivot_offset = _PIVOT
	_shown = visible
	_refresh_translation()


func set_shown(shown: bool, animate: bool = true) -> void:
	if shown == _shown:
		return
	_shown = shown
	if _tween != null:
		_tween.kill()
		_tween = null
	if not animate:
		scale = Vector2.ONE
		visible = shown
		return
	visible = true
	_tween = create_tween()
	var steps: Array = _APPEAR_STEPS if shown else _DISAPPEAR_STEPS
	for step: Array in steps:
		var from_scale: float = step[0]
		var to_scale: float = step[1]
		var curve: Vector4 = step[3]
		_tween.tween_method(
			func(progress: float) -> void:
				scale = (
					Vector2.ONE * lerpf(from_scale, to_scale, CssBezier.evaluate(progress, curve))
				),
			0.0,
			1.0,
			step[2]
		)
	if not shown:
		_tween.tween_callback(hide)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_translation()


func show_reward(kind: String) -> void:
	avatar.visible = kind == "avatar"
	trial_costume.visible = kind == "trial_costume"
	mouse.visible = kind == "mouse"
	permanent_costume.visible = kind == "permanent_costume"
	frame.visible = kind == "frame"


func _refresh_translation() -> void:
	trial_label.text = tr("DC_COSTUME_TRIAL_TAG")
