## 排行榜烟花线条特效；生成 Line2D 轨迹，按寿命与运动曲线逐帧更新并清理节点。

@tool
class_name FireworkLineTrail
extends Node2D

@export_group("Emit")

@export var emitting: bool = false:
	set(v):
		emitting = v
		if v:
			_start_burst()

@export_range(1, 200, 1) var amount: int = 45

@export var seed: int = 955

@export var distribution_seed: int = 12345

@export_group("Life")

@export_range(0.1, 5.0, 0.01, "suffix:s") var lifetime: float = 0.75

@export_range(0.0, 1.0, 0.01) var lifetime_randomness: float = 0.3

@export_group("Velocity")

@export_range(0.0, 180.0, 1.0, "suffix:°") var spread_deg: float = 180.0

@export var initial_velocity_min: float = 104.325

@export var initial_velocity_max: float = 221.325

@export var gravity: Vector2 = Vector2(0.0, 200.0)

@export var damping_min: float = 0.0

@export var damping_max: float = 30.0

@export_group("Curve")

@export var tangential_accel_min: float = 0.0

@export var tangential_accel_max: float = 0.0

@export_group("Trail")

@export_range(1.0, 2000.0, 1.0, "suffix:px") var trail_length: float = 40.0

@export_range(0.1, 200.0, 0.1, "suffix:px") var width_base: float = 8.0

@export_range(0.0, 1.0, 0.01) var shrink_start: float = 0.6

@export var width_curve: Curve

@export var color_gradient: Gradient

@export var color_gradient_2: Gradient

@export var color_gradient_3: Gradient

@export var texture: Texture2D

@export var texture_mode: Line2D.LineTextureMode = Line2D.LINE_TEXTURE_STRETCH

@export var texture_rotate_90: bool = true

@export var additive_blend: bool = true


class _Particle:
	var pos: Vector2
	var vel: Vector2
	var age: float = 0.0
	var life: float = 1.0
	var tangential: float = 0.0
	var damping: float = 0.0
	var gradient: Gradient = null
	var history: PackedVector2Array = PackedVector2Array()
	var line: Line2D


var _particles: Array[_Particle] = []
var _alive: int = 0
var _rng := RandomNumberGenerator.new()
var _dist_rng := RandomNumberGenerator.new()
var _line_mat: Material = null


func _ready() -> void:
	if width_curve == null:
		width_curve = _default_width_curve()
	if color_gradient == null:
		color_gradient = _default_color_gradient()
	set_process(false)


func _start_burst() -> void:
	if not is_inside_tree():
		return
	_clear()
	_rng.seed = seed
	_dist_rng.seed = distribution_seed

	var palettes := _collect_gradients()
	var half_spread := deg_to_rad(spread_deg)
	for i in range(amount):
		var p := _Particle.new()
		p.pos = Vector2.ZERO

		var ang := -PI * 0.5 + _dist_rng.randf_range(-half_spread, half_spread)
		var speed := _rng.randf_range(initial_velocity_min, initial_velocity_max)
		p.vel = Vector2.from_angle(ang) * speed
		p.life = lifetime * (1.0 - _rng.randf() * lifetime_randomness)
		p.life = maxf(p.life, 0.05)
		p.tangential = _rng.randf_range(tangential_accel_min, tangential_accel_max)
		p.damping = _rng.randf_range(damping_min, damping_max)

		if not palettes.is_empty():
			p.gradient = palettes[_rng.randi() % palettes.size()]
		p.history = PackedVector2Array([p.pos])
		p.line = _make_line()

		p.line.gradient = p.gradient
		add_child(p.line)
		_particles.append(p)
	_alive = _particles.size()
	set_process(true)


func _process(delta: float) -> void:
	if _alive <= 0:
		set_process(false)
		return
	for p in _particles:
		if p.line == null:
			continue
		if p.age > p.life:
			continue

		p.vel += gravity * delta

		var v_len := p.vel.length()
		if v_len > 0.001:
			p.vel += (p.vel / v_len).orthogonal() * p.tangential * delta

		v_len = p.vel.length()
		if v_len > 0.001:
			var damp := p.damping * delta
			var new_len := maxf(0.0, v_len - damp)
			p.vel = p.vel / v_len * new_len

		p.pos += p.vel * delta
		p.age += delta
		p.history.append(p.pos)

		var pts := _build_fixed_length_points(p.history)

		if pts.size() < 2:
			p.line.clear_points()
		else:
			p.line.points = pts

			var life_t := p.age / p.life
			var shrink := 1.0
			if life_t > shrink_start and shrink_start < 1.0:
				shrink = clampf(1.0 - (life_t - shrink_start) / (1.0 - shrink_start), 0.0, 1.0)
			p.line.width = width_base * shrink

		if p.age > p.life:
			p.line.clear_points()
			_alive -= 1


func _build_fixed_length_points(history: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := history.size()
	if n < 2:
		return out
	var remaining := trail_length
	var reversed_pts: Array[Vector2] = []
	reversed_pts.append(history[n - 1])
	for i in range(n - 1, 0, -1):
		var from_pos := history[i]
		var to_pos := history[i - 1]
		var seg := from_pos.distance_to(to_pos)
		if is_zero_approx(seg):
			continue
		if remaining >= seg:
			reversed_pts.append(to_pos)
			remaining -= seg
		else:
			var t := clampf(remaining / seg, 0.0, 1.0)
			reversed_pts.append(from_pos.lerp(to_pos, t))
			break
	out.resize(reversed_pts.size())
	for i in range(reversed_pts.size()):
		out[reversed_pts.size() - 1 - i] = reversed_pts[i]
	return out


func _make_line() -> Line2D:
	var line := Line2D.new()
	line.width = width_base
	line.width_curve = width_curve
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	if texture != null:
		line.texture = texture
		line.texture_mode = texture_mode
	line.material = _line_material()
	return line


func _line_material() -> Material:
	if _line_mat != null:
		return _line_mat
	if texture != null and texture_rotate_90:
		var sh := Shader.new()
		var mode := "render_mode blend_add;\n" if additive_blend else ""
		sh.code = (
			"shader_type canvas_item;\n"
			+ mode
			+ "void fragment() {\n"
			+ "\tvec2 uv = vec2(UV.y, 1.0 - UV.x);\n"
			+ "\tCOLOR = texture(TEXTURE, uv) * COLOR;\n"
			+ "}\n"
		)
		var smat := ShaderMaterial.new()
		smat.shader = sh
		_line_mat = smat
		return _line_mat

	var cmat := CanvasItemMaterial.new()
	cmat.blend_mode = (
		CanvasItemMaterial.BLEND_MODE_ADD if additive_blend else CanvasItemMaterial.BLEND_MODE_MIX
	)
	_line_mat = cmat
	return _line_mat


func _collect_gradients() -> Array[Gradient]:
	var result: Array[Gradient] = []
	if color_gradient != null:
		result.append(color_gradient)
	if color_gradient_2 != null:
		result.append(color_gradient_2)
	if color_gradient_3 != null:
		result.append(color_gradient_3)
	return result


func _clear() -> void:
	for p in _particles:
		if p.line != null and is_instance_valid(p.line):
			p.line.queue_free()
	_particles.clear()
	_alive = 0


func _default_width_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.25))
	c.add_point(Vector2(0.8, 1.0))
	c.add_point(Vector2(1.0, 0.1))
	return c


func _default_color_gradient() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.28, 0.6, 1.0])
	g.colors = PackedColorArray(
		[
			Color(1.0, 0.36, 0.72, 1.0),
			Color(0.42, 0.85, 1.0, 1.0),
			Color(0.66, 0.47, 0.97, 1.0),
			Color(0.29, 0.3, 0.98, 1.0),
		]
	)
	return g
