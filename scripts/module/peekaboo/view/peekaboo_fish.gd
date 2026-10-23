## 单条奖励鱼的表现节点；从出现动画过渡到飞行、拖尾和抵达粒子，并发出抵达信号。

extends Node2D

signal first_fish_arrived

signal last_fish_arrived

signal all_fish_arrived

const ANIM_LEFT_SINGLE: StringName = &"LeftFishAppear2"
const ANIM_LEFT_TRIPLE: StringName = &"LeftFishAppear1"
const ANIM_RIGHT_SINGLE: StringName = &"RightFishAppear1"
const ANIM_RIGHT_TRIPLE: StringName = &"RightFishAppear2"

const FISH_NODE_NAMES: Array[StringName] = [&"Fish1", &"Fish2", &"Fish3"]

const DESIGN_VIEWPORT_WIDTH: float = 1080.0

const TRAIL_PATH: String = "Root/ScoreTrail"

const TRAIL_LINE_NAMES: Array[StringName] = [&"TrailAlp", &"TrailGlow", &"TrailAdd"]

const TRAIL_FLIGHT_PARTICLE: StringName = &"Stars"

const TRAIL_STARS_ENABLED: bool = false

const TRAIL_ARRIVE_PARTICLES: Array[StringName] = [&"GlowAlp", &"GlowAdd", &"Point"]

const TRAIL_LENGTH_FROM: float = 1.0
const TRAIL_LENGTH_TO: float = 600.0
const TRAIL_GROW_SEC: float = 0.1

const TRAIL_START_DELAY_SEC: float = 0.2

var _anim_player: AnimationPlayer = null
var _fish_host: Control = null

var _fish_nodes: Array[Control] = []

var _curves: Array[Curve2D] = []

var _timings: Array[Vector4] = []

var _pivot_offsets: Array[Vector2] = []

var _arrived: Array[bool] = []

var _trail_started: Array[bool] = []

var _target_local: Vector2 = Vector2.ZERO

var _elapsed_sec: float = 0.0

var _flying: bool = false

var _finished: bool = true

var _shape_family: StringName = FishFlightCurve.FAMILY_LAYOUT_1

var _flight_duration_sec: float = FishFlightCurve.FLIGHT_DURATION_SEC

var _last_arrived_emitted: bool = false


func _ready() -> void:
	_ensure_nodes()
	set_process(false)


func _ensure_nodes() -> bool:
	if _fish_host == null or not is_instance_valid(_fish_host):
		_fish_host = get_node_or_null("Control") as Control
	if _anim_player == null or not is_instance_valid(_anim_player):
		_anim_player = get_node_or_null("Control/AnimationPlayer") as AnimationPlayer
	return _fish_host != null


func play(
	side_left: bool,
	count: int,
	target_global: Vector2,
	shape_family: StringName = FishFlightCurve.FAMILY_LAYOUT_1,
	duration_sec: float = FishFlightCurve.FLIGHT_DURATION_SEC
) -> void:
	if not _ensure_nodes():
		push_warning("[PeekabooFish] 预制体结构异常（缺 Control 节点），跳过整段表现")
		last_fish_arrived.emit()
		all_fish_arrived.emit()
		return
	var fish_count: int = 3 if count >= 3 else 1
	_shape_family = shape_family
	_flight_duration_sec = maxf(duration_sec, FishFlightCurve.DEGENERATE_DISTANCE)
	_elapsed_sec = 0.0
	_flying = false
	_finished = false
	_last_arrived_emitted = false
	_fish_nodes.clear()
	_curves.clear()
	_timings.clear()
	_pivot_offsets.clear()
	_arrived.clear()
	_trail_started.clear()

	_target_local = _fish_host.get_global_transform().affine_inverse() * target_global

	for index in fish_count:
		var fish: Control = _fish_host.get_node_or_null(String(FISH_NODE_NAMES[index])) as Control
		if fish == null:
			continue
		fish.visible = true
		_fish_nodes.append(fish)
		_curves.append(null)
		_timings.append(Vector4.ZERO)
		_pivot_offsets.append(_visual_pivot_offset(fish))
		_arrived.append(false)
		_trail_started.append(false)

		fish.self_modulate.a = 1.0

	for index in range(fish_count, FISH_NODE_NAMES.size()):
		var idle_fish: Control = (
			_fish_host.get_node_or_null(String(FISH_NODE_NAMES[index])) as Control
		)
		if idle_fish != null:
			idle_fish.visible = false

	var anim_name: StringName = _pick_appear_anim(side_left, fish_count)
	if _anim_player != null and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
	else:
		push_warning("[PeekabooFish] 缺动画 %s，跳过跳出段直接进飞行" % anim_name)

	set_process(true)


func _pick_appear_anim(side_left: bool, fish_count: int) -> StringName:
	if side_left:
		return ANIM_LEFT_TRIPLE if fish_count >= 3 else ANIM_LEFT_SINGLE
	return ANIM_RIGHT_TRIPLE if fish_count >= 3 else ANIM_RIGHT_SINGLE


func _visual_pivot_offset(fish: Control) -> Vector2:
	var ratio: Vector2 = Vector2(0.5, 0.5)
	if fish.pivot_offset_ratio != Vector2.ZERO:
		ratio = fish.pivot_offset_ratio
	return fish.size * ratio


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_sec += delta

	if not _flying:
		if _elapsed_sec < FishFlightCurve.APPEAR_TO_FLIGHT_SEC:
			return
		_begin_flight()

	var flight_elapsed: float = _elapsed_sec - FishFlightCurve.APPEAR_TO_FLIGHT_SEC
	var all_done: bool = true
	for index in _fish_nodes.size():
		var fish: Control = _fish_nodes[index]
		if fish == null or not is_instance_valid(fish):
			continue
		var local_elapsed: float = flight_elapsed - FishFlightCurve.launch_delay(index)
		if local_elapsed < 0.0:
			all_done = false
			continue
		if not _trail_started[index] and local_elapsed >= TRAIL_START_DELAY_SEC:
			_trail_started[index] = true
			_start_trail(fish)
		var pivot_position: Vector2 = FishFlightCurve.sample_flight_position(
			_curves[index], _timings[index], local_elapsed, _flight_duration_sec
		)
		fish.position = pivot_position - _pivot_offsets[index]
		if local_elapsed >= _flight_duration_sec:
			if not _arrived[index]:
				_arrived[index] = true
				if index == 0:
					first_fish_arrived.emit()

				_emit_arrive_particles(fish)

				fish.self_modulate.a = 0.0
		else:
			all_done = false

	if all_done and not _last_arrived_emitted:
		_last_arrived_emitted = true
		last_fish_arrived.emit()

	if all_done and flight_elapsed >= _flight_span_sec() + FishFlightCurve.ARRIVE_HOLD_SEC:
		_finished = true
		set_process(false)
		all_fish_arrived.emit()


func _begin_flight() -> void:
	_flying = true

	if _anim_player != null and _anim_player.is_playing():
		_anim_player.pause()

	for index in _fish_nodes.size():
		var fish: Control = _fish_nodes[index]
		if fish == null or not is_instance_valid(fish):
			continue
		var start_pivot: Vector2 = fish.position + _pivot_offsets[index]
		var role: FishFlightCurve.Role = FishFlightCurve.role_for_index(index)
		var template: Dictionary = FishFlightCurve.get_template(_shape_family, role)
		_curves[index] = FishFlightCurve.build_runtime_curve(
			template, start_pivot, _target_local, _side_sign_for(start_pivot)
		)
		_timings[index] = template["timing_bezier"]


func _side_sign_for(start_pivot: Vector2) -> float:
	if _fish_host == null:
		return 1.0

	var viewport_width: float = DESIGN_VIEWPORT_WIDTH
	if _fish_host.is_inside_tree():
		var measured_width: float = _fish_host.get_viewport_rect().size.x
		if measured_width > 0.0:
			viewport_width = measured_width
	var global_x: float = (_fish_host.get_global_transform() * start_pivot).x
	return 1.0 if global_x < viewport_width * 0.5 else -1.0


func _start_trail(fish: Control) -> void:
	var trail: Node = fish.get_node_or_null(TRAIL_PATH)
	if trail == null:
		push_warning("[PeekabooFish] %s 缺 %s，本条鱼无拖尾" % [fish.name, TRAIL_PATH])
		return

	if trail.has_method("clear_trail"):
		trail.call("clear_trail")
	var trail_item: CanvasItem = trail as CanvasItem
	if trail_item != null:
		trail_item.visible = true
	for line_name in TRAIL_LINE_NAMES:
		var line: CanvasItem = trail.get_node_or_null(String(line_name)) as CanvasItem
		if line != null:
			line.visible = true
	var stars: CPUParticles2D = (
		trail.get_node_or_null(String(TRAIL_FLIGHT_PARTICLE)) as CPUParticles2D
	)
	if stars != null:
		stars.visible = TRAIL_STARS_ENABLED
		stars.emitting = false
	trail.set("fixed_trail_length", TRAIL_LENGTH_FROM)
	var grow_tween: Tween = (trail as Node).create_tween()
	grow_tween.tween_property(trail, "fixed_trail_length", TRAIL_LENGTH_TO, TRAIL_GROW_SEC)


func _emit_arrive_particles(fish: Control) -> void:
	var trail: Node = fish.get_node_or_null(TRAIL_PATH)
	if trail == null:
		return
	for particle_name in TRAIL_ARRIVE_PARTICLES:
		var particles: CPUParticles2D = (
			trail.get_node_or_null(String(particle_name)) as CPUParticles2D
		)
		if particles != null:
			particles.visible = true
			particles.one_shot = true
			particles.emitting = true


func _flight_span_sec() -> float:
	if _fish_nodes.size() <= 1:
		return _flight_duration_sec
	return FishFlightCurve.launch_delay(_fish_nodes.size() - 1) + _flight_duration_sec
