## 棋盘图案扫描叠层：根据格子几何生成轮廓线并播放扫光，取消时清理视觉状态。
extends CanvasLayer

signal effect_finished

const _DIM_SHADER: Shader = preload("res://assets/shaders/board_pattern_dim.gdshader")
const _HIGHLIGHT_SHADER: Shader = preload("res://assets/shaders/board_pattern_highlight.gdshader")
const _OUTLINE_TEXTURE: Texture2D = preload("res://assets/effect/texture/line/et_line_003.png")

const _FADE_IN_END_SEC: float = 0.2
const _HOLD_END_SEC: float = 0.6
const _SWEEP_END_SEC: float = 0.4333
const _TOTAL_DURATION_SEC: float = 0.8333
const _DIM_MAX_ALPHA: float = 0.35 / 2
const _MASK_MARGIN_PX: float = 24.0
const _OUTLINE_WIDTH_PX: float = 64.0

var _dim_rect: ColorRect
var _outline_root: Node2D
var _highlight_rect: ColorRect
var _dim_material: ShaderMaterial
var _highlight_material: ShaderMaterial
var _cell_mask_texture: ImageTexture
var _effect_rect: Rect2

var _board_rect: Rect2
var _configured: bool = false
var _tween: Tween
var _play_token: int = 0


func _ready() -> void:
	layer = 20
	_ensure_nodes()


func configure(board_view: BoardView, region_map: Array, special_region_ids: Array) -> bool:
	_ensure_nodes()
	cancel()
	_clear_outline_lines()
	_configured = false
	if board_view == null or region_map.is_empty() or special_region_ids.is_empty():
		return false

	var special_ids: Dictionary = {}
	for raw_id: Variant in special_region_ids:
		special_ids[int(raw_id)] = true

	var size_n: int = region_map.size()
	if size_n <= 0:
		return false
	_board_rect = _transform_rect(
		Rect2(Vector2.ZERO, board_view.size), board_view.get_global_transform()
	)
	if _board_rect.size.x <= 0.0 or _board_rect.size.y <= 0.0:
		return false
	var special_flags: Array = []
	var cell_rects: Array[Rect2] = []
	var special_rects: Array[Rect2] = []
	for r: int in range(size_n):
		var row_flags: Array[bool] = []
		var row: Array = region_map[r] if region_map[r] is Array else []
		for c: int in range(size_n):
			var is_special: bool = c < row.size() and special_ids.has(int(row[c]))
			row_flags.append(is_special)
			var local_rect: Rect2 = board_view.cell_to_local_rect(r, c)
			var global_rect: Rect2 = _transform_rect(local_rect, board_view.get_global_transform())
			cell_rects.append(global_rect)
			if is_special:
				special_rects.append(global_rect)
		special_flags.append(row_flags)

	if special_rects.is_empty():
		return false

	var gap_x: float = 0.0
	var gap_y: float = 0.0
	if size_n > 1:
		gap_x = maxf(0.0, cell_rects[1].position.x - cell_rects[0].end.x)
		gap_y = maxf(0.0, cell_rects[size_n].position.y - cell_rects[0].end.y)
	var half_gap_x: float = gap_x * 0.5
	var half_gap_y: float = gap_y * 0.5

	var bounds: Rect2 = special_rects[0]
	for r: int in range(size_n):
		for c: int in range(size_n):
			if not bool(special_flags[r][c]):
				continue
			var index: int = r * size_n + c
			var shape_rect: Rect2 = cell_rects[index].grow_individual(
				half_gap_x, half_gap_y, half_gap_x, half_gap_y
			)
			bounds = bounds.merge(shape_rect)

	var bounds_pos: Vector2 = Vector2(
		floorf(bounds.position.x - _MASK_MARGIN_PX), floorf(bounds.position.y - _MASK_MARGIN_PX)
	)
	var bounds_end: Vector2 = Vector2(
		ceilf(bounds.end.x + _MASK_MARGIN_PX), ceilf(bounds.end.y + _MASK_MARGIN_PX)
	)
	_effect_rect = Rect2(bounds_pos, bounds_end - bounds_pos)
	var image_size: Vector2i = Vector2i(
		maxi(1, int(_effect_rect.size.x)), maxi(1, int(_effect_rect.size.y))
	)

	var cell_image: Image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_L8)
	cell_image.fill(Color.BLACK)
	for rect: Rect2 in special_rects:
		cell_image.fill_rect(_to_local_recti(rect), Color.WHITE)

	_cell_mask_texture = ImageTexture.create_from_image(cell_image)
	var contours: Array[PackedVector2Array] = _build_outline_contours(
		special_flags, cell_rects, size_n, half_gap_x, half_gap_y
	)
	if contours.is_empty():
		return false
	_create_outline_lines(contours)
	_apply_geometry()
	_configured = true
	return true


func play() -> void:
	if not _configured:
		effect_finished.emit()
		return
	cancel()
	_play_token += 1
	var token: int = _play_token
	_dim_rect.visible = true
	_outline_root.visible = true
	_highlight_rect.visible = true
	_apply_elapsed(0.0)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_apply_elapsed, 0.0, _TOTAL_DURATION_SEC, _TOTAL_DURATION_SEC)
	_tween.finished.connect(
		func() -> void:
			if token != _play_token:
				return
			_finish_effect(),
		CONNECT_ONE_SHOT
	)


func cancel() -> void:
	_play_token += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _dim_rect != null:
		_dim_rect.visible = false
	if _outline_root != null:
		_outline_root.visible = false
	if _highlight_rect != null:
		_highlight_rect.visible = false
	_apply_elapsed(0.0)


func _ensure_nodes() -> void:
	if _dim_rect != null:
		return
	_dim_material = ShaderMaterial.new()
	_dim_material.shader = _DIM_SHADER
	_highlight_material = ShaderMaterial.new()
	_highlight_material.shader = _HIGHLIGHT_SHADER

	_dim_rect = ColorRect.new()
	_dim_rect.name = "PatternDim"
	_dim_rect.color = Color.WHITE
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rect.material = _dim_material
	_dim_rect.visible = false
	add_child(_dim_rect)

	_outline_root = Node2D.new()
	_outline_root.name = "PatternOutline"
	_outline_root.visible = false
	add_child(_outline_root)

	_highlight_rect = ColorRect.new()
	_highlight_rect.name = "PatternHighlight"
	_highlight_rect.color = Color.WHITE
	_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_rect.material = _highlight_material
	_highlight_rect.visible = false
	add_child(_highlight_rect)


func _apply_geometry() -> void:
	_dim_rect.position = _board_rect.position
	_dim_rect.size = _board_rect.size
	_highlight_rect.position = _effect_rect.position
	_highlight_rect.size = _effect_rect.size

	var normalized_rect := Vector4(
		(_effect_rect.position.x - _board_rect.position.x) / _board_rect.size.x,
		(_effect_rect.position.y - _board_rect.position.y) / _board_rect.size.y,
		_effect_rect.size.x / _board_rect.size.x,
		_effect_rect.size.y / _board_rect.size.y
	)
	_dim_material.set_shader_parameter("mask_texture", _cell_mask_texture)
	_dim_material.set_shader_parameter("mask_rect", normalized_rect)

	_dim_material.set_shader_parameter("rect_size_px", _board_rect.size)
	_dim_material.set_shader_parameter("corner_radius_px", float(BoardView.BOARD_BG_CORNER_RADIUS))
	_highlight_material.set_shader_parameter("cell_mask", _cell_mask_texture)
	_highlight_material.set_shader_parameter("sweep_half_width_px", 180.0)
	_highlight_material.set_shader_parameter("rect_size_px", _effect_rect.size)


func _apply_elapsed(elapsed: float) -> void:
	if _dim_material == null or _highlight_material == null:
		return
	var dim_alpha: float
	var outline_alpha: float
	if elapsed < _FADE_IN_END_SEC:
		var intro_t: float = clampf(elapsed / _FADE_IN_END_SEC, 0.0, 1.0)
		dim_alpha = lerpf(0.0, _DIM_MAX_ALPHA, intro_t)
		outline_alpha = intro_t
	elif elapsed < _HOLD_END_SEC:
		dim_alpha = _DIM_MAX_ALPHA
		outline_alpha = 1.0
	else:
		var outro_t: float = clampf(
			(elapsed - _HOLD_END_SEC) / (_TOTAL_DURATION_SEC - _HOLD_END_SEC), 0.0, 1.0
		)
		dim_alpha = lerpf(_DIM_MAX_ALPHA, 0.0, outro_t)
		outline_alpha = lerpf(1.0, 0.0, outro_t)
	var sweep_progress: float = clampf(elapsed / _SWEEP_END_SEC, 0.0, 1.0)
	_dim_material.set_shader_parameter("dim_alpha", dim_alpha)
	_outline_root.modulate = Color(1.0, 1.0, 1.0, outline_alpha)
	_highlight_material.set_shader_parameter("sweep_progress", sweep_progress)


func _finish_effect() -> void:
	_apply_elapsed(_TOTAL_DURATION_SEC)
	_dim_rect.visible = false
	_outline_root.visible = false
	_highlight_rect.visible = false
	_tween = null
	effect_finished.emit()


func _clear_outline_lines() -> void:
	if _outline_root == null:
		return
	for child: Node in _outline_root.get_children():
		_outline_root.remove_child(child)
		child.queue_free()


func _create_outline_lines(contours: Array[PackedVector2Array]) -> void:
	for contour: PackedVector2Array in contours:
		if contour.size() < 3:
			continue
		var line := Line2D.new()
		line.name = "Outline"
		line.points = contour
		line.closed = true
		line.width = _OUTLINE_WIDTH_PX
		line.texture = _OUTLINE_TEXTURE

		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.round_precision = 8
		line.antialiased = true
		_outline_root.add_child(line)


func _build_outline_contours(
	special_flags: Array,
	cell_rects: Array[Rect2],
	size_n: int,
	half_gap_x: float,
	half_gap_y: float
) -> Array[PackedVector2Array]:
	var edges: Array = []
	for r: int in range(size_n):
		for c: int in range(size_n):
			if not bool(special_flags[r][c]):
				continue
			var rect: Rect2 = cell_rects[r * size_n + c].grow_individual(
				half_gap_x, half_gap_y, half_gap_x, half_gap_y
			)
			var top_left: Vector2 = rect.position
			var top_right := Vector2(rect.end.x, rect.position.y)
			var bottom_right: Vector2 = rect.end
			var bottom_left := Vector2(rect.position.x, rect.end.y)
			if r == 0 or not bool(special_flags[r - 1][c]):
				edges.append([top_left, top_right])
			if c == size_n - 1 or not bool(special_flags[r][c + 1]):
				edges.append([top_right, bottom_right])
			if r == size_n - 1 or not bool(special_flags[r + 1][c]):
				edges.append([bottom_right, bottom_left])
			if c == 0 or not bool(special_flags[r][c - 1]):
				edges.append([bottom_left, top_left])
	return _trace_contours(edges)


func _trace_contours(edges: Array) -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	while not edges.is_empty():
		var first_edge: Array = edges.pop_back()
		var start: Vector2 = first_edge[0]
		var current: Vector2 = first_edge[1]
		var incoming: Vector2 = current - start
		var points := PackedVector2Array([start, current])
		var closed: bool = _points_equal(current, start)
		while not closed and not edges.is_empty():
			var next_index: int = _select_next_edge(edges, current, incoming)
			if next_index < 0:
				break
			var next_edge: Array = edges[next_index]
			edges.remove_at(next_index)
			incoming = next_edge[1] - current
			current = next_edge[1]
			closed = _points_equal(current, start)
			if not closed:
				points.append(current)
		if closed and points.size() >= 3:
			contours.append(_simplify_contour(points))
	return contours


func _select_next_edge(edges: Array, current: Vector2, incoming: Vector2) -> int:
	var best_index: int = -1
	var best_priority: int = 99
	for i: int in range(edges.size()):
		if not _points_equal(edges[i][0], current):
			continue
		var outgoing: Vector2 = edges[i][1] - current
		var cross: float = incoming.cross(outgoing)
		var dot: float = incoming.dot(outgoing)

		var priority: int
		if cross > 0.01:
			priority = 0
		elif dot > 0.0:
			priority = 1
		elif cross < -0.01:
			priority = 2
		else:
			priority = 3
		if priority < best_priority:
			best_priority = priority
			best_index = i
	return best_index


func _simplify_contour(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 3:
		return points
	var simplified := PackedVector2Array()
	var count: int = points.size()
	for i: int in range(count):
		var prev: Vector2 = points[(i - 1 + count) % count]
		var current: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % count]
		var incoming: Vector2 = current - prev
		var outgoing: Vector2 = next - current
		if absf(incoming.cross(outgoing)) > 0.01:
			simplified.append(current)
	return simplified


func _points_equal(a: Vector2, b: Vector2) -> bool:
	return a.distance_squared_to(b) < 0.01


func _to_local_recti(global_rect: Rect2) -> Rect2i:
	var local_pos: Vector2 = global_rect.position - _effect_rect.position
	var local_end: Vector2 = global_rect.end - _effect_rect.position
	var start_i := Vector2i(floori(local_pos.x), floori(local_pos.y))
	var end_i := Vector2i(ceili(local_end.x), ceili(local_end.y))
	return Rect2i(start_i, end_i - start_i)


func _transform_rect(rect: Rect2, transform: Transform2D) -> Rect2:
	var p0: Vector2 = transform * rect.position
	var p1: Vector2 = transform * Vector2(rect.end.x, rect.position.y)
	var p2: Vector2 = transform * rect.end
	var p3: Vector2 = transform * Vector2(rect.position.x, rect.end.y)
	var min_pos := Vector2(
		minf(minf(p0.x, p1.x), minf(p2.x, p3.x)), minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	)
	var max_pos := Vector2(
		maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)), maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	)
	return Rect2(min_pos, max_pos - min_pos)
