## 局内排行收集器；显示当前收集数，提供奖励鱼的目标坐标，并处理胜利时延迟揭示与粒子反馈。

class_name RankCollectorCell
extends UIChildWindow

@onready var _control: Control = $Control
@onready var _icon: TextureRect = $Control/Icon
@onready var _count_label: RichTextLabel = $Control/CountLabel
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _fish_burst: Node = $Particle/FishBurst

var _is_golden_fish: bool = false

var _flight_displayed: int = 0

var _flight_final_count: int = -1

var _flight_collect_started: bool = false

var _win_reveal_deferred: bool = false

var _win_reveal_pending: bool = false


func on_create() -> void:
	connect_managed(RankActivityManager.ranking_changed, _on_rank_win)
	visible = false


func hide_and_reset() -> void:
	cancel_deferred_win_reveal()
	if _anim != null and _anim.is_playing():
		_anim.stop()
	if _anim != null and _anim.has_animation("RESET"):
		_anim.play("RESET")
	_flight_displayed = 0
	_flight_final_count = -1
	_flight_collect_started = false
	_apply_count(0)
	visible = false


func set_win_reveal_deferred(deferred: bool) -> void:
	_win_reveal_deferred = deferred
	if not deferred and _win_reveal_pending:
		_win_reveal_pending = false
		_on_rank_win()


func cancel_deferred_win_reveal() -> void:
	_win_reveal_deferred = false
	_win_reveal_pending = false


func set_golden_fish(is_gf: bool) -> void:
	_is_golden_fish = is_gf


func set_collect_icon_above_z(z: int) -> void:
	if _icon != null:
		_icon.z_index = z


func _apply_count(value: float) -> void:
	if _count_label != null:
		_count_label.text = "[color=#935A5A]%d[/color]" % int(round(value))


func _on_rank_win() -> void:
	var game_page: UIFrameWindow = UIManager.get_ui(UiName.GAME)
	if game_page == null or not game_page.is_showing():
		return
	if _win_reveal_deferred:
		_win_reveal_pending = true
		return

	if (
		not _is_golden_fish
		and ABTestManager.leaderboard_collection_levelwin.is_settle_page_flight()
	):
		return

	var increment: int = RankActivityManager.get_last_win_base_increment()
	if increment <= 0:
		return
	_flight_displayed = 0
	_flight_final_count = -1
	_flight_collect_started = false
	_apply_count(0)
	visible = true

	if _anim != null and _anim.has_animation("Appear"):
		_anim.play("Appear")


## 接收局内收集反馈并更新显示；活动真实计分仍在 RankActivityManager 的结算路径。
func on_item_collected() -> void:
	if not _flight_collect_started:
		VibrateManager.play_at(VibrateManager.Pos.RANK_COLLECTOR_FLY)
	if _flight_final_count < 0 or _flight_displayed < _flight_final_count:
		_flight_displayed += 1
	_apply_count(_flight_displayed)
	_emit_burst()
	if not _flight_collect_started:
		_flight_collect_started = true

		if _control != null:
			_control.modulate = Color(1, 1, 1, 1)
		if _anim != null and _anim.has_animation("Collect"):
			_anim.play("Collect")


## 把可能滞后的动画显示对齐实际收集值，避免快进或延迟揭示后仍显示旧数字。
func settle_count_to_actual() -> void:
	var increment: int = RankActivityManager.get_last_win_base_increment()
	_flight_final_count = increment
	if increment <= _flight_displayed:
		return
	_flight_displayed = increment
	_apply_count(_flight_displayed)


func _emit_burst() -> void:
	var burst: Node = _fish_burst
	if burst == null or not is_instance_valid(burst):
		return
	var dup: Node = (burst as Node).duplicate()
	burst.get_parent().add_child(dup)
	var max_life: float = 0.0
	for p: Node in dup.find_children("*", "CPUParticles2D", true, false):
		var particle := p as CPUParticles2D
		if particle != null:
			particle.restart()
			particle.emitting = true
			max_life = maxf(max_life, particle.lifetime)

	var tw: Tween = dup.create_tween()
	tw.tween_interval(max_life + 0.3)
	tw.tween_callback(dup.queue_free)


func get_collect_target_global() -> Vector2:
	if _icon != null and is_instance_valid(_icon):
		return _icon.global_position + _icon.size * _icon.get_global_transform().get_scale() / 2.0
	return global_position
