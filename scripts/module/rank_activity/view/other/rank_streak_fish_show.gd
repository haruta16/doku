## 连胜倍率额外奖励鱼的演出；统一规划生成、发射、爆发粒子与抵达时序。

class_name RankStreakFishShow
extends RefCounted

const _FISH_SCENE: PackedScene = preload("res://assets/prefab/effect_double_fish.tscn")
const _ERUPT_SCENE: PackedScene = preload("res://assets/prefab/effect_double_erupt.tscn")

const MAX_FISH: int = 6

const _UP_APPEAR_AT: float = 1.467
const _UP_APPEAR_GAP: float = 0.033

const _UP_SCATTER: Array = [
	[1.6, 1.817], [1.634, 1.85], [1.667, 1.917], [1.7, 1.984], [1.734, 2.034]
]
const _UP_ERUPT_AT: float = 1.6
const _UP_PLUS_AT: float = 1.7837
const _UP_FLY_AT: float = 2.55
const _UP_FLY_GAP: float = 0.067

const _SAME_APPEAR: Array = [0.683, 0.783, 0.85]
const _SAME_APPEAR_GAP: float = 0.067
const _SAME_SCATTER_AT: float = 0.817
const _SAME_SCATTER_GAP: float = 0.034
const _SAME_SCATTER_DUR: float = 0.216
const _SAME_ERUPT_AT: float = 0.817
const _SAME_PLUS_AT: float = 1.0
const _SAME_FLY_AT: float = 1.767
const _SAME_FLY_GAP: float = 0.0667

const _FLY_DUR: float = 0.567

const _FLY_C1_OFFSET: Vector2 = Vector2(-133.66, 169.196)
const _FLY_C2_OFFSET: Vector2 = Vector2(-378.366, -299.135)
const _FLY_PODIUM_C1_OFFSET: Vector2 = Vector2(-175.479, 46.772)
const _FLY_PODIUM_C2_OFFSET: Vector2 = Vector2(-116.912, -174.564)
const _FLY_TIMING: Vector4 = Vector4(0.42, 0.0, 0.58, 1.0)

const _SCATTER_OFFSETS: Array[Vector2] = [
	Vector2(-35.4, -35.4),
	Vector2(35.4, -35.4),
	Vector2(-35.4, 35.4),
	Vector2(35.4, 35.4),
	Vector2(0.0, 50.0),
]

const _FISH_LIFE_TAIL: float = 0.1

const _ERUPT_FREE_PAD: float = 0.3

var layer: Control

var clock: Callable

var alive: Callable

var register: Callable

var release: Callable

var fish_z: int = 0

var arrive_scale: float = 1.0

var to_podium: bool = false


static func fly_path(from: Vector2, to: Vector2, podium: bool) -> Curve2D:
	var path := Curve2D.new()
	path.add_point(from, Vector2.ZERO, _FLY_PODIUM_C1_OFFSET if podium else _FLY_C1_OFFSET)
	path.add_point(to, _FLY_PODIUM_C2_OFFSET if podium else _FLY_C2_OFFSET, Vector2.ZERO)
	return path


static func timeline(count: int, tier_up: bool) -> Dictionary:
	var n: int = clampi(count, 0, MAX_FISH)
	var appear: Array[float] = []
	var scatter_from: Array[float] = []
	var scatter_to: Array[float] = []
	var fly: Array[float] = []
	var arrive: Array[float] = []
	for k in n:
		var appear_at: float
		var fly_at: float
		if tier_up:
			appear_at = _UP_APPEAR_AT + _UP_APPEAR_GAP * k
			fly_at = _UP_FLY_AT + _UP_FLY_GAP * k
		else:
			if k < _SAME_APPEAR.size():
				appear_at = float(_SAME_APPEAR[k])
			else:
				appear_at = (
					float(_SAME_APPEAR[_SAME_APPEAR.size() - 1])
					+ _SAME_APPEAR_GAP * (k - _SAME_APPEAR.size() + 1)
				)
			fly_at = _SAME_FLY_AT + _SAME_FLY_GAP * k
		appear.append(appear_at)
		fly.append(fly_at)
		arrive.append(fly_at + _FLY_DUR)
		if k == 0:
			scatter_from.append(appear_at)
			scatter_to.append(appear_at)
		elif tier_up:
			var window: Array = _UP_SCATTER[k - 1]
			scatter_from.append(float(window[0]))
			scatter_to.append(float(window[1]))
		else:
			var from_at: float = maxf(_SAME_SCATTER_AT + _SAME_SCATTER_GAP * (k - 1), appear_at)
			scatter_from.append(from_at)
			scatter_to.append(from_at + _SAME_SCATTER_DUR)
	return {
		"count": n,
		"appear": appear,
		"scatter_from": scatter_from,
		"scatter_to": scatter_to,
		"fly": fly,
		"arrive": arrive,
		"erupt": _UP_ERUPT_AT if tier_up else _SAME_ERUPT_AT,
		"plus": _UP_PLUS_AT if tier_up else _SAME_PLUS_AT,
		"first_arrive": arrive[0] if n > 0 else 0.0,
		"last_arrive": arrive[n - 1] if n > 0 else 0.0,
	}


static func reseed_particles(root: Node) -> void:
	var particles: Array[Node] = root.find_children("*", "CPUParticles2D", true, false)
	var new_seeds: Dictionary = {}
	for node in particles:
		var particle := node as CPUParticles2D
		if particle != null and particle.use_fixed_seed and not new_seeds.has(particle.seed):
			new_seeds[particle.seed] = randi()
	for node in particles:
		var particle := node as CPUParticles2D
		if particle != null and particle.use_fixed_seed:
			particle.seed = new_seeds[particle.seed]


## 按统一时间线生成倍率奖励鱼与爆发特效；结束回调让主页面等待整个演出完成。
func play(
	center: Vector2,
	count: int,
	tier_up: bool,
	to_provider: Callable,
	on_launch: Callable,
	on_arrive: Callable
) -> void:
	var plan: Dictionary = timeline(count, tier_up)
	var n: int = int(plan["count"])
	if n <= 0 or layer == null:
		return
	_at(float(plan["erupt"]), _spawn_erupt.bind(center))
	for k in n:
		_at(
			float(plan["appear"][k]),
			_spawn_fish.bind(k, center, plan, to_provider, on_launch, on_arrive)
		)


func _spawn_fish(
	order: int,
	center: Vector2,
	plan: Dictionary,
	to_provider: Callable,
	on_launch: Callable,
	on_arrive: Callable
) -> void:
	var appear_at: float = float(plan["appear"][order])
	var fish := _FISH_SCENE.instantiate() as CPUParticles2D
	fish.lifetime = float(plan["arrive"][order]) - appear_at + _FISH_LIFE_TAIL
	fish.z_index = fish_z
	layer.add_child(fish)
	fish.global_position = center
	register.call(fish)
	fish.restart()
	fish.emitting = true
	if order >= 1 and order - 1 < _SCATTER_OFFSETS.size():
		var from_at: float = float(plan["scatter_from"][order])
		var to_at: float = float(plan["scatter_to"][order])
		var scatter := fish.create_tween()
		(
			scatter
			. tween_property(
				fish,
				"global_position",
				center + _SCATTER_OFFSETS[order - 1],
				maxf(0.01, to_at - from_at)
			)
			. set_delay(maxf(0.0, from_at - float(clock.call())))
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
	_at(float(plan["fly"][order]), _launch.bind(fish, order, to_provider, on_launch, on_arrive))


func _launch(
	fish: CPUParticles2D,
	order: int,
	to_provider: Callable,
	on_launch: Callable,
	on_arrive: Callable
) -> void:
	if not is_instance_valid(fish):
		return
	on_launch.call(order)
	var from: Vector2 = fish.global_position
	var to: Vector2 = to_provider.call()
	var path: Curve2D = fly_path(from, to, to_podium)
	var length: float = path.get_baked_length()
	if not is_equal_approx(arrive_scale, 1.0):
		var shrink := fish.create_tween()
		(
			shrink
			. tween_property(fish, "scale", Vector2.ONE * arrive_scale, _FLY_DUR)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN)
		)
	var fly := fish.create_tween()
	fly.tween_method(
		func(progress: float) -> void:
			fish.global_position = path.sample_baked(
				CssBezier.evaluate(progress, _FLY_TIMING) * length
			),
		0.0,
		1.0,
		_FLY_DUR
	)
	fly.tween_callback(
		func() -> void:
			if alive.call():
				on_arrive.call()
			release.call(fish)
	)


func _spawn_erupt(center: Vector2) -> void:
	var erupt := _ERUPT_SCENE.instantiate() as Control
	erupt.z_index = fish_z
	layer.add_child(erupt)
	erupt.global_position = center
	register.call(erupt)
	reseed_particles(erupt)
	var max_life: float = 0.0
	var particles: Array[Node] = erupt.find_children("*", "CPUParticles2D", true, false)
	for node in particles:
		var particle := node as CPUParticles2D
		particle.restart()
		particle.emitting = true
		max_life = maxf(max_life, particle.lifetime)
	var cleanup := erupt.create_tween()
	cleanup.tween_interval(max_life + _ERUPT_FREE_PAD)
	cleanup.tween_callback(release.bind(erupt))


func _at(at_sec: float, action: Callable) -> void:
	var delay: float = at_sec - float(clock.call())
	if delay <= 0.0:
		if alive.call():
			action.call()
		return
	layer.get_tree().create_timer(delay).timeout.connect(
		func() -> void:
			if alive.call():
				action.call()
	)
