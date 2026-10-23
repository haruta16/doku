## 打卡图标视图：按实验组切换美术和点亮姿态，并提供统一缩放与动画时间查询。
extends Control
class_name StreakDayIcon

const _UNCHECKED_CHILD: String = "Unchecked"

const _EFFECT_NODE: String = "EffectErupt"

const _LIGHT_UP_EFFECT_NODE: String = "LightUpEffect"

@export var auto_idle_loop: bool = true

@export var is_checked_state: bool = true

@export var owns_checked_visual: bool = true

@onready var _forms: Control = $Control

var _anim: AnimationPlayer = null

var _active_form: CanvasItem = null

var _lighting_up: bool = false

var _checkin_generation: int = 0


func _ready() -> void:
	_apply_group()


func play_checkin_anim(start_delay: float = 0.0, preferred_animation: StringName = &"") -> void:
	var group: int = StreakManager.get_effective_icon_group()
	var anim_name: StringName = ABTestManager.dailystreak_icon.checkin_anim(group)

	var animation_player: AnimationPlayer = _anim

	if (
		animation_player != null
		and preferred_animation != &""
		and animation_player.has_animation(preferred_animation)
	):
		anim_name = preferred_animation
	if animation_player == null or not animation_player.has_animation(anim_name):
		push_error(
			(
				"StreakDayIcon: 分组 %d 的打卡过渡动画 %s 不在该形态的 AnimationLibrary 中"
				% [
					group,
					anim_name,
				]
			)
		)
		return

	_checkin_generation += 1
	var generation: int = _checkin_generation
	_lighting_up = true
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
		if generation != _checkin_generation:
			return
		if not is_inside_tree() or animation_player != _anim:
			_lighting_up = false
			return
	animation_player.play(anim_name)

	var idle_name: StringName = ABTestManager.dailystreak_icon.idle_loop_anim(group)
	if idle_name == &"":
		var hold: float = animation_player.get_animation(anim_name).length
		if hold > 0.0:
			await get_tree().create_timer(hold).timeout
		if generation != _checkin_generation:
			return

		if animation_player == _anim:
			_lighting_up = false
		return

	var delay: float = ABTestManager.dailystreak_icon.idle_loop_delay(group)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	else:
		await animation_player.animation_finished
	if generation != _checkin_generation:
		return

	if is_inside_tree() and animation_player == _anim and animation_player.has_animation(idle_name):
		animation_player.play(idle_name)
		flush_pose()
	_lighting_up = false


func refresh_group(checked: bool = true) -> void:
	is_checked_state = checked
	_apply_group()


func get_checkin_animation_position(animation_name: StringName) -> float:
	if _anim == null or not _anim.is_playing() or _anim.current_animation != animation_name:
		return -1.0
	return _anim.current_animation_position


func get_checkin_swing_times(animation_name: StringName) -> Array[float]:
	var times: Array[float] = []
	if _anim == null or not _anim.has_animation(animation_name):
		return times
	var animation: Animation = _anim.get_animation(animation_name)
	var track: int = animation.find_track(^"R:rotation", Animation.TYPE_BEZIER)
	if track < 0:
		return times
	for key_index: int in animation.track_get_key_count(track):
		var rotation: float = animation.bezier_track_get_key_value(track, key_index)
		if not is_zero_approx(rotation):
			times.append(animation.track_get_key_time(track, key_index))
	return times


func fit_design(
	base_height: float, center: Vector2 = Vector2.INF, per_state: bool = false
) -> Vector2:
	var cfg: DailystreakIconConfig = ABTestManager.dailystreak_icon
	var group: int = StreakManager.get_effective_icon_group()
	var want_h: float = cfg.design_icon_size(group).y * (base_height / cfg.DESIGN_BASE_HEIGHT)
	return _fit_height(want_h, center, per_state)


func fit_uniform_height(
	height: float, center: Vector2 = Vector2.INF, per_state: bool = false
) -> Vector2:
	return _fit_height(height, center, per_state)


const CANVAS_SIZE: float = 512.0


func fit_canvas(canvas_height: float, center: Vector2 = Vector2.INF) -> Vector2:
	var k: float = canvas_height / CANVAS_SIZE
	scale = Vector2.ONE * k

	_forms.position = Vector2.ZERO
	var got: Vector2 = Vector2(CANVAS_SIZE, CANVAS_SIZE) * k
	if not is_inf(center.x):
		position = center - got * 0.5
	return got


func _fit_height(target_height: float, center: Vector2, per_state: bool = false) -> Vector2:
	var cfg: DailystreakIconConfig = ABTestManager.dailystreak_icon
	var group: int = StreakManager.get_effective_icon_group()
	var rect: Rect2 = cfg.canvas_content_rect(group)

	var k: float = target_height / rect.size.y
	scale = Vector2.ONE * k

	_forms.position = -rect.position
	var got: Vector2 = rect.size * k

	var mid: Vector2 = rect.size * 0.5
	if per_state:
		mid = cfg.canvas_content_center(group) - rect.position
	if not is_inf(center.x):
		position = center - mid * k
	elif per_state:
		position = got * 0.5 - mid * k

	return got


func flush_pose() -> void:
	if not is_visible_in_tree() or _active_form == null:
		return
	if _anim != null and _anim.current_animation != &"":
		_anim.advance(0.0)


func reset_icon() -> void:
	_checkin_generation += 1
	_lighting_up = false
	if _anim == null:
		return
	if not _anim.has_animation(&"RESET"):
		_anim.stop()
		return
	_anim.play(&"RESET")

	_anim.advance(0.0)


func _apply_group() -> void:
	var cfg: DailystreakIconConfig = ABTestManager.dailystreak_icon

	var group: int = StreakManager.get_effective_icon_group()
	var want: StringName = cfg.icon_node_name(group)
	_active_form = null

	for form_name: StringName in cfg.all_form_node_names():
		var child: Node = _forms.get_node_or_null(String(form_name))
		if child == null or not (child is CanvasItem):
			continue
		var hit: bool = form_name == want
		(child as CanvasItem).visible = hit
		if hit:
			_active_form = child as CanvasItem

	if _active_form == null:
		_anim = null
		push_error(
			(
				"StreakDayIcon: 分组 %d(checked=%s) 期望的形态节点 %s 不在预制中"
				% [
					group,
					str(is_checked_state),
					want,
				]
			)
		)
		return

	_anim = _active_form.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim == null:
		push_error("StreakDayIcon: 形态 %s 下缺 AnimationPlayer 子节点(分组 %d)" % [want, group])

	_apply_checked_state()
	_apply_idle_state()

	flush_pose()


func _apply_idle_state() -> void:
	if _lighting_up:
		return
	if _anim == null:
		return
	var group: int = StreakManager.get_effective_icon_group()
	var idle_name: StringName = ABTestManager.dailystreak_icon.idle_loop_anim(group)
	if is_checked_state:
		if idle_name != &"" and _anim.has_animation(idle_name) and auto_idle_loop:
			_anim.play(idle_name)
			return

		_anim.stop()
		_apply_checked_state()
		return

	var unchecked_name: StringName = ABTestManager.dailystreak_icon.unchecked_anim(group)
	if unchecked_name != &"" and _anim.has_animation(unchecked_name):
		_anim.play(unchecked_name)
		return

	if not owns_checked_visual and not ABTestManager.dailystreak_icon.has_unchecked_art(group):
		_anim.stop()
		_force_checked_art()
		return

	if _anim.has_animation(&"RESET"):
		_anim.play(&"RESET")
	else:
		_anim.stop()


func _apply_checked_state() -> void:
	if _active_form == null:
		return

	if _lighting_up:
		return

	var art_group: int = StreakManager.get_effective_icon_group()
	if ABTestManager.dailystreak_icon.has_unchecked_art(art_group):
		_switch_unchecked_child()
		if owns_checked_visual and not is_checked_state:
			_active_form.modulate.a = ABTestManager.dailystreak_icon.unchecked_alpha(art_group)
		else:
			_active_form.modulate.a = 1.0
		return

	if not owns_checked_visual:
		if _active_form.get_node_or_null(_UNCHECKED_CHILD) != null:
			_force_checked_art()
		return
	var has_two_arts: bool = _active_form.get_node_or_null(_UNCHECKED_CHILD) != null
	if has_two_arts:
		_switch_unchecked_child()
		_active_form.modulate.a = 1.0
	else:
		_active_form.modulate.a = (
			1.0
			if is_checked_state
			else ABTestManager.dailystreak_icon.unchecked_alpha(
				StreakManager.get_effective_icon_group()
			)
		)


func _switch_unchecked_child() -> void:
	var unchecked: Node = _active_form.find_child(_UNCHECKED_CHILD, true, false)
	var visual_parent: Node = unchecked.get_parent() if unchecked != null else _active_form

	if visual_parent != _active_form and visual_parent is CanvasItem:
		var visual_container: CanvasItem = visual_parent as CanvasItem
		visual_container.visible = true
		visual_container.modulate.a = 1.0
	var visual_children: Array[Node] = visual_parent.get_children()
	for child: Node in visual_children:
		if child is CanvasItem:
			var ci: CanvasItem = child as CanvasItem
			if String(child.name) == _LIGHT_UP_EFFECT_NODE:
				continue

			if String(child.name) == _EFFECT_NODE or ci is CPUParticles2D:
				ci.visible = true
				ci.modulate.a = 1.0
				continue
			var is_unchecked: bool = String(child.name) == _UNCHECKED_CHILD

			ci.visible = true
			ci.modulate.a = 1.0 if (is_unchecked != is_checked_state) else 0.0


func _force_checked_art() -> void:
	if _active_form == null:
		return
	for child: Node in _active_form.get_children():
		if not (child is CanvasItem):
			continue
		var ci: CanvasItem = child as CanvasItem
		if String(child.name) == _LIGHT_UP_EFFECT_NODE:
			continue
		if String(child.name) == _EFFECT_NODE or ci is CPUParticles2D:
			continue
		ci.visible = true
		ci.modulate.a = 0.0 if String(child.name) == _UNCHECKED_CHILD else 1.0
