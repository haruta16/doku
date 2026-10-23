## 预放猫聚光灯表现：按棋盘与视口几何布置灯光、猫和粒子镜像。
extends PreCatFxVariant

const _SHADER_DIM: Shader = preload("res://assets/shaders/pre_cat_spotlight_dim.gdshader")
const _SHADER_LIGHT: Shader = preload("res://assets/shaders/pre_cat_spotlight_light.gdshader")
const _TEX_BEAM: Texture2D = preload("res://assets/effect/texture/spotlight/et_spotlight_beam.png")
const _TEX_POOL: Texture2D = preload("res://assets/effect/texture/spotlight/et_spotlight_pool.png")
const _TEX_LAMP: Texture2D = preload("res://assets/effect/texture/spotlight/et_spotlight_lamp.png")
const _TEX_KNOCK: Texture2D = preload(
	"res://assets/effect/texture/spotlight/et_spotlight_knockout.png"
)

const _LOCK_WOBBLE_ENABLED: bool = true

const _AIM_SWING_CELLS: float = 1.0

const _FALLBACK_BOARD_TOP_Y: float = 696.0

const _DIM_IN_SEC: float = 0.25
const _AIM_SEC: float = 0.45
const _HOLD_SEC: float = 0.9
const _FADE_OUT_SEC: float = 0.4

@export var dim_alpha_peak: float = 0.6

@export var knock_size_px: float = 522.0

@export var pool_size_px: float = 228.0

@export_enum("正常混合", "加色(Add)", "滤色(Screen)") var light_blend_mode: int = 2

@export var lamp_size_px: float = 204.0

@export var lamp_offset_from_board_px: Vector2 = Vector2(-3.0, -70.0)

@export var beam_start_width_ratio: float = 1.33

@export var beam_end_width_ratio: float = 1.26

@export var beam_overshoot_px: float = 232.0

@export var beam_tex_v_cap: float = 0.4

@export var beam_fade_start_pool_scale: float = 1.26

var _ctx: PreCatFxContext = null
var _dim: ColorRect = null
var _light: ColorRect = null
var _lamp: TextureRect = null

var _cat_mirror: SpineSprite = null

var _cat_mirror_anim: String = ""

var _particle_mirror: Control = null
var _mat_dim: ShaderMaterial = null
var _mat_light: ShaderMaterial = null

var _lamp_center: Vector2 = Vector2.ZERO

var _metrics: Dictionary = {}


func nominal_duration_sec() -> float:
	return _DIM_IN_SEC + _AIM_SEC + _HOLD_SEC + _FADE_OUT_SEC


func setup(ctx: PreCatFxContext) -> void:
	_ctx = ctx
	_ensure_nodes()
	_apply_geometry(ctx.cat_cell)
	_set_intensity(0.0, 0.0)

	_stop_cat_mirror()


func play() -> void:
	if _ctx == null or _mat_dim == null:
		await get_tree().process_frame
		return

	var tw: Tween = create_tween()

	tw.tween_method(_tween_dim_only, 0.0, 1.0, _DIM_IN_SEC)

	if _LOCK_WOBBLE_ENABLED:
		tw.tween_method(_tween_aim, 0.0, 1.0, _AIM_SEC)
	else:
		tw.tween_method(_tween_light_only, 0.0, 1.0, _AIM_SEC)
	await tw.finished

	if _ctx.reveal_cat.is_valid():
		_ctx.reveal_cat.call(true, false, "PreCat2")
	_start_cat_mirror()

	var hold: Tween = create_tween()
	hold.tween_interval(_HOLD_SEC)
	await hold.finished

	var out_tw: Tween = create_tween()
	out_tw.tween_method(_tween_fade_out, 0.0, 1.0, _FADE_OUT_SEC)
	await out_tw.finished

	_stop_cat_mirror()


func debug_apply_locked(cat_cell: Vector2i) -> Dictionary:
	_ensure_nodes()
	_apply_geometry(cat_cell)
	_set_intensity(dim_alpha_peak, 1.0)

	_start_cat_mirror()
	return _metrics.duplicate()


func _ensure_nodes() -> void:
	if _dim != null and is_instance_valid(_dim):
		return

	_mat_dim = ShaderMaterial.new()
	_mat_dim.shader = _SHADER_DIM
	_mat_dim.set_shader_parameter("knock_tex", _TEX_KNOCK)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 1)
	_dim.material = _mat_dim
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_mat_light = ShaderMaterial.new()
	_mat_light.shader = _SHADER_LIGHT
	_mat_light.set_shader_parameter("beam_tex", _TEX_BEAM)
	_mat_light.set_shader_parameter("pool_tex", _TEX_POOL)
	_light = ColorRect.new()
	_light.name = "Light"
	_light.color = Color(1, 1, 1, 1)
	_light.material = _mat_light
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_light)

	_lamp = _make_sprite("Lamp", _TEX_LAMP)

	_cat_mirror = SpineSprite.new()
	_cat_mirror.name = "CatMirror"
	_cat_mirror.visible = false

	var src_for_skel := _ctx.cat_icon_source as SpineSprite if _ctx != null else null
	var skel_res: SpineSkeletonDataResource = (
		src_for_skel.get_skeleton_data_res()
		if src_for_skel != null and is_instance_valid(src_for_skel)
		else CostumeSkin.SKELETON_RES
	)
	_cat_mirror.skeleton_data_res = skel_res
	add_child(_cat_mirror)

	if _ctx != null and _ctx.particles_source != null and is_instance_valid(_ctx.particles_source):
		_particle_mirror = _ctx.particles_source.duplicate() as Control
		if _particle_mirror != null:
			_particle_mirror.name = "ParticleMirror"
			_particle_mirror.visible = false
			add_child(_particle_mirror)
			move_child(_particle_mirror, _cat_mirror.get_index())
	set_process(false)


func _make_sprite(node_name: String, tex: Texture2D) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = node_name
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(rect)
	return rect


func _apply_geometry(cat_cell: Vector2i) -> void:
	if _ctx == null or _mat_dim == null:
		return

	_lamp_center = _resolve_lamp_center()

	var cell_rect: Rect2 = _ctx.cell_rect_global
	if cat_cell != _ctx.cat_cell and _ctx.board != null:
		cell_rect = _cell_rect_of(cat_cell)
	var cat_center: Vector2 = cell_rect.get_center()

	var axis: Vector2 = cat_center - _lamp_center
	var cat_dist: float = maxf(axis.length(), 1.0)

	var rect_px: Vector2 = _dim.size
	if rect_px.x <= 0.0 or rect_px.y <= 0.0:
		rect_px = get_viewport_rect().size

	_mat_dim.set_shader_parameter("rect_size_px", rect_px)
	_mat_dim.set_shader_parameter("knock_center_px", cat_center)
	_mat_dim.set_shader_parameter("knock_size_px", knock_size_px)

	_mat_light.set_shader_parameter("rect_size_px", rect_px)
	_mat_light.set_shader_parameter("blend_mode", light_blend_mode)
	_mat_light.set_shader_parameter("beam_from_px", _lamp_center)
	_mat_light.set_shader_parameter("beam_top_width_px", beam_start_width_ratio * pool_size_px)
	_mat_light.set_shader_parameter("beam_bottom_width_px", beam_end_width_ratio * pool_size_px)
	_mat_light.set_shader_parameter("beam_tex_v_cap", beam_tex_v_cap)
	_mat_light.set_shader_parameter("pool_size_px", pool_size_px)
	_apply_beam_axis(cat_center, cat_dist)

	_place_cat_mirror()

	_place_particle_mirror(cell_rect)

	_place_centered(_lamp, _lamp_center, lamp_size_px)
	_lamp.pivot_offset = _lamp.size * 0.5
	_lamp.rotation = axis.angle() - PI * 0.5

	var top_px: float = beam_start_width_ratio * pool_size_px
	var end_px: float = beam_end_width_ratio * pool_size_px
	var half_width_delta: float = (end_px - top_px) * 0.5
	var cone_deg: float = rad_to_deg(2.0 * atan(half_width_delta / cat_dist))
	var cell: float = maxf(_ctx.cell_size_px, 1.0)
	var axis_dir: Vector2 = axis / cat_dist
	_metrics = {
		"cell": Vector2i(cat_cell),
		"lamp_anchor": _lamp_center,
		"board_top_y": _ctx.board_rect_global.position.y,
		"cat_center": cat_center,
		"beam_end": cat_center + axis_dir * beam_overshoot_px,
		"cat_dist_px": cat_dist,
		"length_px": cat_dist + beam_overshoot_px,
		"overshoot_px": beam_overshoot_px,
		"top_width_px": top_px,
		"bottom_width_px": end_px,
		"top_width_cells": top_px / cell,
		"bottom_width_cells": end_px / cell,
		"width_px": end_px,
		"width_cells": end_px / cell,
		"cone_deg": cone_deg,
		"pool_px": pool_size_px,
		"knock_px": knock_size_px,
		"cell_px": cell,
		"tilt_deg": rad_to_deg(atan2(axis.x, axis.y)),
	}


func _resolve_lamp_center() -> Vector2:
	var board_rect: Rect2 = _ctx.board_rect_global if _ctx != null else Rect2()
	var center_x: float = board_rect.position.x + board_rect.size.x * 0.5
	var top_y: float = board_rect.position.y
	if board_rect.size.x <= 0.0 or board_rect.size.y <= 0.0:
		center_x = get_viewport_rect().size.x * 0.5
		top_y = _FALLBACK_BOARD_TOP_Y
	return Vector2(center_x, top_y) + lamp_offset_from_board_px


func _apply_beam_axis(target: Vector2, dist: float) -> void:
	if _mat_light == null:
		return
	var axis_dir: Vector2 = target - _lamp_center
	var safe_dist: float = maxf(dist, 1.0)
	axis_dir = axis_dir / safe_dist

	var over: float = minf(beam_overshoot_px, _ray_dist_to_viewport_edge(target, axis_dir))
	var total_len: float = maxf(safe_dist + over, 1.0)
	var fade_radius: float = pool_size_px * 0.5 * beam_fade_start_pool_scale
	_mat_light.set_shader_parameter("beam_to_px", target + axis_dir * over)
	_mat_light.set_shader_parameter("beam_cat_v", clampf(safe_dist / total_len, 0.05, 1.0))
	_mat_light.set_shader_parameter(
		"beam_fade_v", clampf((safe_dist - fade_radius) / total_len, 0.0, 0.999)
	)

	_mat_light.set_shader_parameter("pool_center_px", target)


func _ray_dist_to_viewport_edge(origin: Vector2, dir: Vector2) -> float:
	var size: Vector2 = get_viewport_rect().size
	var t: float = INF
	if dir.x > 0.0001:
		t = minf(t, (size.x - origin.x) / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, (0.0 - origin.x) / dir.x)
	if dir.y > 0.0001:
		t = minf(t, (size.y - origin.y) / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, (0.0 - origin.y) / dir.y)
	return maxf(t, 0.0)


func _place_cat_mirror() -> void:
	if _cat_mirror == null or not is_instance_valid(_cat_mirror) or _ctx == null:
		return
	var src: Node2D = _ctx.cat_icon_source
	if src == null or not is_instance_valid(src):
		return
	_cat_mirror.global_transform = src.global_transform


func _place_particle_mirror(cell_rect: Rect2) -> void:
	if _particle_mirror == null or not is_instance_valid(_particle_mirror) or _ctx == null:
		return
	var src: Control = _ctx.particles_source
	if src == null or not is_instance_valid(src):
		return
	_particle_mirror.scale = src.scale * _ctx.board_scale
	_particle_mirror.position = cell_rect.position + src.position * _ctx.board_scale


func _start_cat_mirror() -> void:
	if _cat_mirror == null or not is_instance_valid(_cat_mirror):
		return
	if _ctx == null or _ctx.cat_icon_source == null or not is_instance_valid(_ctx.cat_icon_source):
		return

	var src_spine := _ctx.cat_icon_source as SpineSprite
	if src_spine != null and is_instance_valid(src_spine):
		var mirror_skel: SpineSkeleton = _cat_mirror.get_skeleton()
		var src_skel: SpineSkeleton = src_spine.get_skeleton()
		if mirror_skel != null and src_skel != null:
			mirror_skel.set_skin(src_skel.get_skin())

			mirror_skel.set_slots_to_setup_pose()
	_sync_cat_mirror()
	_cat_mirror.visible = true
	if _particle_mirror != null and is_instance_valid(_particle_mirror):
		_particle_mirror.visible = true
	set_process(true)


func _stop_cat_mirror() -> void:
	set_process(false)
	if _cat_mirror != null and is_instance_valid(_cat_mirror):
		_cat_mirror.visible = false
	if _particle_mirror != null and is_instance_valid(_particle_mirror):
		_particle_mirror.visible = false
	_cat_mirror_anim = ""


func _process(_delta: float) -> void:
	_sync_cat_mirror()


func _sync_cat_mirror() -> void:
	var src: Node2D = _ctx.cat_icon_source if _ctx != null else null
	if (
		src == null
		or not is_instance_valid(src)
		or _cat_mirror == null
		or not is_instance_valid(_cat_mirror)
	):
		_stop_cat_mirror()
		return
	_cat_mirror.modulate = src.modulate
	var src_spine := src as SpineSprite
	if src_spine != null and is_instance_valid(src_spine):
		var src_state: SpineAnimationState = src_spine.get_animation_state()
		var mirror_state: SpineAnimationState = _cat_mirror.get_animation_state()
		if src_state != null and mirror_state != null:
			var src_entry: SpineTrackEntry = src_state.get_current(0)
			if src_entry != null:
				var anim_name: String = src_entry.get_animation().get_name()
				var mirror_entry: SpineTrackEntry = mirror_state.get_current(0)
				if anim_name != _cat_mirror_anim or mirror_entry == null:
					_cat_mirror_anim = anim_name
					mirror_entry = mirror_state.set_animation(anim_name, src_entry.get_loop(), 0)
				if mirror_entry != null:
					mirror_entry.set_track_time(src_entry.get_track_time())

	var psrc: Control = _ctx.particles_source if _ctx != null else null
	if (
		_particle_mirror != null
		and is_instance_valid(_particle_mirror)
		and psrc != null
		and is_instance_valid(psrc)
	):
		var real_ps: Array = psrc.find_children("*", "CPUParticles2D", true, false)
		var mir_ps: Array = _particle_mirror.find_children("*", "CPUParticles2D", true, false)
		for i in range(mini(real_ps.size(), mir_ps.size())):
			(mir_ps[i] as CPUParticles2D).emitting = (real_ps[i] as CPUParticles2D).emitting


func _place_centered(rect: TextureRect, center: Vector2, size_px: float) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	var w: float = size_px
	var h: float = size_px
	var tex: Texture2D = rect.texture
	if tex != null and tex.get_width() > 0:
		h = w * float(tex.get_height()) / float(tex.get_width())
	rect.size = Vector2(w, h)
	rect.position = center - Vector2(w, h) * 0.5


func _cell_rect_of(cell: Vector2i) -> Rect2:
	var local: Rect2 = _ctx.board.cell_to_local_rect(cell.x, cell.y)
	var xf: Transform2D = _ctx.board.get_global_transform()
	var p0: Vector2 = xf * local.position
	var p1: Vector2 = xf * Vector2(local.end.x, local.position.y)
	var p2: Vector2 = xf * local.end
	var p3: Vector2 = xf * Vector2(local.position.x, local.end.y)
	var lo := Vector2(
		minf(minf(p0.x, p1.x), minf(p2.x, p3.x)), minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	)
	var hi := Vector2(
		maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)), maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	)
	return Rect2(lo, hi - lo)


func _set_intensity(dim_a: float, light_a: float) -> void:
	if _dim != null and is_instance_valid(_dim):
		_dim.modulate.a = clampf(dim_a, 0.0, 1.0)
	var la: float = clampf(light_a, 0.0, 1.0)

	if _mat_dim != null:
		_mat_dim.set_shader_parameter("knock_alpha", la)

	if _mat_light != null:
		_mat_light.set_shader_parameter("light_alpha", la)
	if _lamp != null and is_instance_valid(_lamp):
		_lamp.modulate.a = la


func _tween_dim_only(t: float) -> void:
	_set_intensity(dim_alpha_peak * t, 0.0)


func _tween_light_only(t: float) -> void:
	_set_intensity(dim_alpha_peak, t)


func _tween_aim(t: float) -> void:
	var swing_cells: float = _AIM_SWING_CELLS * (1.0 - t) * (1.0 - t)
	var offset: Vector2 = Vector2(
		sin(t * TAU * 2.0) * swing_cells * maxf(_ctx.cell_size_px, 1.0), 0.0
	)
	_aim_at(Vector2(_metrics.get("cat_center", Vector2.ZERO)) + offset)
	_set_intensity(dim_alpha_peak, t)


func _tween_fade_out(t: float) -> void:
	_aim_at(Vector2(_metrics.get("cat_center", Vector2.ZERO)))
	_set_intensity(dim_alpha_peak * (1.0 - t), 1.0 - t)


func _aim_at(target: Vector2) -> void:
	if _mat_light == null or _mat_dim == null:
		return
	_apply_beam_axis(target, (target - _lamp_center).length())
	_mat_dim.set_shader_parameter("knock_center_px", target)
