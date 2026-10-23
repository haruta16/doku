## 排行榜点赞按钮的表现与反馈；维护选中、透明度和数字变化动画，实际点赞状态由活动管理器持有。

class_name RankHeart
extends Control

const _NUMBER_CHANGE_DELAY: float = 0.13

@onready var _heart_empty: TextureRect = $Control/HeartEmpty
@onready var _heart_full: TextureRect = $Control/HeartFull
@onready var _heart_num: Label = $HeartNum
@onready var _heart_num2: Label = $HeartNum2
@onready var _icon_control: Control = $Control
@onready var _heart_full_glow_1: TextureRect = $HeartFullGlow1
@onready var _heart_full_glow_2: TextureRect = $HeartFullGlow2
@onready var _particle: CPUParticles2D = $Particle
@onready var _animation: AnimationPlayer = $AnimationPlayer
@onready var _heart_btn: Button = $HeartBtn

var _number_change_tween: Tween = null
var _like_target_id: String = ""
var _pressed_callback: Callable = Callable()


func _ready() -> void:
	_heart_btn.pressed.connect(_on_heart_button_pressed)


func configure_like_display(
	shown: bool,
	heart_count: int = 0,
	filled: bool = false,
	use_inner_number: bool = false,
	target_id: String = "",
	animate: bool = false,
	on_pressed: Callable = Callable(),
	empty_alpha: float = 1.0,
	unliked_inner_number_alpha: float = 1.0
) -> void:
	_like_target_id = target_id if shown else ""
	_pressed_callback = on_pressed if shown else Callable()
	visible = shown
	if not shown:
		reset_like_state()
		_heart_btn.disabled = true
		return
	set_like_state(
		heart_count, filled, use_inner_number, animate, empty_alpha, unliked_inner_number_alpha
	)
	_heart_btn.disabled = _like_target_id.is_empty() or not _pressed_callback.is_valid()


func is_like_target(target_id: String) -> bool:
	return not target_id.is_empty() and _like_target_id == target_id


func _on_heart_button_pressed() -> void:
	if _like_target_id.is_empty() or not _pressed_callback.is_valid():
		return
	_pressed_callback.call(_like_target_id)


## 更新点赞外观并按需播放反馈；数字变化可能延迟到动画节点，因此下一次更新前要取消旧任务。
func set_like_state(
	heart_count: int,
	filled: bool,
	use_inner_number: bool,
	animate: bool = false,
	empty_alpha: float = 1.0,
	unliked_inner_number_alpha: float = 1.0
) -> void:
	_set_number_layout(use_inner_number)
	_set_like_alpha(filled, empty_alpha, unliked_inner_number_alpha)
	_cancel_pending_number_change()
	if not animate:
		_stop_feedback_animation()
		_set_heart_filled(filled)
		_set_number_text(heart_count)
		return
	_stop_feedback_animation()
	_animation.play(&"Like" if filled else &"Cancel")
	_number_change_tween = create_tween()
	_number_change_tween.tween_interval(_NUMBER_CHANGE_DELAY)
	_number_change_tween.tween_callback(_set_number_text.bind(heart_count))


## 清理上一次反馈并恢复基线，供排行行被回收或绑定其他玩家时使用。
func reset_like_state() -> void:
	_cancel_pending_number_change()
	_stop_feedback_animation()
	_set_heart_filled(false)


func _set_number_layout(use_inner_number: bool) -> void:
	_heart_num.visible = not use_inner_number
	_heart_num2.visible = use_inner_number


func _set_heart_filled(filled: bool) -> void:
	_heart_empty.visible = not filled
	_heart_full.visible = filled


func _set_like_alpha(filled: bool, empty_alpha: float, unliked_inner_number_alpha: float) -> void:
	_heart_empty.self_modulate.a = clampf(empty_alpha, 0.0, 1.0)
	_heart_full.self_modulate.a = 1.0
	_heart_num2.self_modulate.a = 1.0 if filled else clampf(unliked_inner_number_alpha, 0.0, 1.0)


func _set_number_text(heart_count: int) -> void:
	var count_text: String = str(maxi(0, heart_count))
	_heart_num.text = count_text
	_heart_num2.text = count_text
	_number_change_tween = null


func _cancel_pending_number_change() -> void:
	if _number_change_tween != null and _number_change_tween.is_valid():
		_number_change_tween.kill()
	_number_change_tween = null


func _stop_feedback_animation() -> void:
	_animation.stop()
	_icon_control.scale = Vector2.ONE
	_heart_full_glow_1.modulate.a = 0.0
	_heart_full_glow_2.modulate.a = 0.0
	_particle.emitting = false
