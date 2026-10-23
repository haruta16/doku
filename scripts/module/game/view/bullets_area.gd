## 弹幕显示区域：按波次准备内容和轨道，管理异步播放、排版及取消后的节点清理。
class_name BulletsArea
extends Control

signal barrage_displayed(key: String)
signal barrage_spawn_failed(key: String)

const SCENE_PATH: String = "res://assets/prefab/bullets_area.tscn"
const BULLET_SCENE: PackedScene = preload("res://scripts/module/rank_activity/ui/rank_bullet.tscn")
const PAGE_HEADER_PATH: NodePath = ^"Root/VBoxContainer/Header"
const PAGE_RULE_BAR_PATH: NodePath = ^"Root/VBoxContainer/RuleBar"
const MIN_AREA_HEIGHT: float = 312.0

const DESIGN_AREA_HEIGHT: float = 404.0

const DESIGN_HEIGHT_STEP: float = 124.0
const DESIGN_LANE_GAP: float = 20.0
const DESIGN_EDGE_MARGIN: float = 42.0
const BULLET_SCALE: float = 0.855

var _generation: int = 0
var _bullets: Array[RankBullet] = []
var _pending_bullets: Array[RankBullet] = []
var _inline_icon_textures: Array[Texture2D] = []
var _layout_page: Node = null
var _layout_host: Control = null
var _layout_header: Control = null
var _layout_rule_bar: Control = null
var _layout_container: Container = null
var _layout_refresh_queued: bool = false
var _layout_active: bool = false


func _ready() -> void:
	_cache_inline_icons()


func _cache_inline_icons() -> void:
	for icon_path_value: Variant in GameBarrageLogic.INLINE_ICON_PATHS.values():
		var texture: Texture2D = ResourceLoader.load(str(icon_path_value)) as Texture2D
		if texture != null:
			_inline_icon_textures.append(texture)


static func ensure_on_page(page: Node, host: Control, before_node: Node = null) -> BulletsArea:
	if page == null or host == null:
		push_error("BulletsArea: page and host are required")
		return null
	var existing: Node = page.find_child("BulletsArea", true, false)
	if existing != null:
		if existing is BulletsArea:
			var existing_area: BulletsArea = existing as BulletsArea
			existing_area._bind_page_layout(page, host)
			return existing_area
		push_error("BulletsArea: node named BulletsArea has wrong type: %s" % existing.get_class())
		return null
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("BulletsArea: failed to load %s" % SCENE_PATH)
		return null
	var area: BulletsArea = scene.instantiate() as BulletsArea
	if area == null:
		push_error("BulletsArea: scene root must be BulletsArea")
		return null
	host.add_child(area)
	if before_node != null and before_node.get_parent() == host:
		host.move_child(area, before_node.get_index())
	area._bind_page_layout(page, host)
	return area


func play_wave(wave: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	if wave.is_empty():
		return
	_refresh_layout_from_bounds()
	var prepared_bullets: Array[RankBullet] = _prepare_wave(wave)
	_play_wave_async(wave, prepared_bullets, rng, _generation)


func set_layout_active(active: bool) -> void:
	if active == _layout_active:
		if active:
			_queue_layout_refresh()
		return
	_layout_active = active
	_queue_layout_refresh()


func cancel_pending() -> void:
	_generation += 1
	for bullet: RankBullet in _pending_bullets:
		if is_instance_valid(bullet):
			bullet.stop_motion()
			bullet.queue_free()
	_pending_bullets.clear()


func clear_all() -> void:
	cancel_pending()
	for bullet: RankBullet in _bullets:
		if is_instance_valid(bullet):
			bullet.stop_motion()
			bullet.queue_free()
	_bullets.clear()


func _prepare_wave(wave: Array[Dictionary]) -> Array[RankBullet]:
	var prepared_bullets: Array[RankBullet] = []
	for barrage: Dictionary in wave:
		var key: String = str(barrage.get("key", ""))
		var bullet: RankBullet = BULLET_SCENE.instantiate() as RankBullet
		if bullet == null:
			barrage_spawn_failed.emit(key)
			prepared_bullets.append(null)
			continue
		bullet.visible = false
		bullet.scale = Vector2(BULLET_SCALE, BULLET_SCALE)
		add_child(bullet)
		bullet.set_barrage(barrage)
		_pending_bullets.append(bullet)
		prepared_bullets.append(bullet)
	return prepared_bullets


func _play_wave_async(
	wave: Array[Dictionary],
	prepared_bullets: Array[RankBullet],
	rng: RandomNumberGenerator,
	generation: int
) -> void:
	var schedule: Array[Dictionary] = RankLikeLogic.make_barrage_schedule(wave.size(), rng)
	for barrage_index: int in wave.size():
		if generation != _generation:
			return
		var barrage: Dictionary = wave[barrage_index]
		var schedule_item: Dictionary = schedule[barrage_index]
		_start_prepared_barrage(
			prepared_bullets[barrage_index], barrage, int(schedule_item.lane_index)
		)
		if barrage_index < wave.size() - 1:
			await get_tree().create_timer(float(schedule_item.next_delay_sec)).timeout


func _calculate_lane_top_positions(area_height: float, bullet_height: float) -> PackedFloat32Array:
	var lane_gap: float
	if area_height <= DESIGN_AREA_HEIGHT:
		var height_ratio: float = _area_height_ratio(area_height)
		var edge_margin: float = lerpf(0.0, DESIGN_EDGE_MARGIN, height_ratio)
		lane_gap = minf(
			(area_height - bullet_height * 3.0 - edge_margin * 2.0) * 0.5, DESIGN_LANE_GAP
		)
	else:
		var extra_height_ratio: float = (area_height - DESIGN_AREA_HEIGHT) / DESIGN_HEIGHT_STEP
		var growing_lane_gap: float = DESIGN_LANE_GAP * (1.0 + extra_height_ratio)
		var largest_fitting_gap: float = (area_height - bullet_height * 3.0) * 0.5
		lane_gap = minf(growing_lane_gap, largest_fitting_gap)
	var cluster_height: float = bullet_height * 3.0 + lane_gap * 2.0
	var first_lane_y: float = (area_height - cluster_height) * 0.5
	return PackedFloat32Array(
		[
			first_lane_y,
			first_lane_y + bullet_height + lane_gap,
			first_lane_y + (bullet_height + lane_gap) * 2.0,
		]
	)


func _area_height_ratio(area_height: float) -> float:
	return clampf((area_height - MIN_AREA_HEIGHT) / DESIGN_HEIGHT_STEP, 0.0, 1.0)


func _align_lanes(bullet_height: float) -> void:
	var start_x: float = size.x
	var lane_positions: PackedFloat32Array = _calculate_lane_top_positions(size.y, bullet_height)
	for lane_index: int in range(1, 4):
		var lane: Control = get_node_or_null("Pos%d" % lane_index) as Control
		if lane != null:
			lane.position = Vector2(start_x, lane_positions[lane_index - 1])


func _bind_page_layout(page: Node, host: Control) -> void:
	_layout_page = page
	_layout_host = host
	if not host.resized.is_connected(_queue_layout_refresh):
		host.resized.connect(_queue_layout_refresh)
	_refresh_layout_nodes()
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_queue_layout_refresh):
		viewport.size_changed.connect(_queue_layout_refresh)
	_queue_layout_refresh()


func _refresh_layout_nodes() -> bool:
	if not is_instance_valid(_layout_page):
		return false
	var header: Control = _layout_page.get_node_or_null(PAGE_HEADER_PATH) as Control
	var rule_bar: Control = _layout_page.get_node_or_null(PAGE_RULE_BAR_PATH) as Control
	if header == null or rule_bar == null:
		return false
	_layout_header = header
	_layout_rule_bar = rule_bar
	_layout_container = header.get_parent() as Container
	if not header.resized.is_connected(_queue_layout_refresh):
		header.resized.connect(_queue_layout_refresh)
	if not rule_bar.resized.is_connected(_queue_layout_refresh):
		rule_bar.resized.connect(_queue_layout_refresh)
	if (
		_layout_container != null
		and not _layout_container.sort_children.is_connected(_queue_layout_refresh)
	):
		_layout_container.sort_children.connect(_queue_layout_refresh)
	return true


func _queue_layout_refresh() -> void:
	if _layout_refresh_queued or not is_inside_tree():
		return
	_layout_refresh_queued = true
	call_deferred("_refresh_layout_from_bounds")


func _refresh_layout_from_bounds() -> void:
	_layout_refresh_queued = false
	if not is_instance_valid(_layout_host) or not _refresh_layout_nodes():
		return
	var host_inverse: Transform2D = _layout_host.get_global_transform_with_canvas().affine_inverse()
	var header_bottom: Vector2 = (
		host_inverse
		* (_layout_header.get_global_transform_with_canvas() * Vector2(0.0, _layout_header.size.y))
	)
	var rule_bar_bottom: Vector2 = (
		host_inverse
		* (
			_layout_rule_bar.get_global_transform_with_canvas()
			* Vector2(0.0, _layout_rule_bar.size.y)
		)
	)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = header_bottom.y
	offset_right = 0.0
	offset_bottom = rule_bar_bottom.y


func _start_prepared_barrage(bullet: RankBullet, barrage: Dictionary, lane_index: int) -> void:
	var key: String = str(barrage.get("key", ""))
	if not is_instance_valid(bullet):
		return
	_pending_bullets.erase(bullet)
	var lane: Control = get_node_or_null("Pos%d" % (lane_index + 1)) as Control
	if lane == null:
		bullet.queue_free()
		barrage_spawn_failed.emit(key)
		return
	var visual_width: float = bullet.size.x * absf(bullet.scale.x)
	var visual_height: float = bullet.size.y * absf(bullet.scale.y)
	_align_lanes(visual_height)
	_bullets.append(bullet)
	bullet.visible = true
	bullet.start_moving(lane.position, -visual_width)
	barrage_displayed.emit(key)
