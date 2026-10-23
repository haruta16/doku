## 区域提示的填色与发光层：沿区域边界构造圆角轮廓，支持淡入、呼吸和淡出。
class_name RegionHighlightOverlay
extends Node2D

const _GLOW_TEXTURE: Texture2D = preload("res://assets/effect/texture/line/et_line_005.png")
const _GLOW_TINT_SHADER: Shader = preload("res://assets/shaders/region_alert_glow_tint.gdshader")

const FILL_OFFSET_PX: float = 2.0
const GLOW_OFFSET_PX: float = 3.0

const FILL_CONVEX_EXTRA_PX: float = 4.6
const FILL_CONCAVE_EXTRA_PX: float = 6.6

const FILL_ALPHA: float = 200.0 / 255.0

const GLOW_WIDTH_PX: float = 49.8

const GLOW_CORE_FROM: float = 0.6
const GLOW_CORE_TO: float = 1.0

const BREATH_SEC: float = 1.0

const FADE_IN_SEC: float = 0.1

const FADE_OUT_SEC: float = 0.12

const GLOW_Z_INDEX: int = CellView.CAT_LAYER_Z_INDEX + 1

var board: BoardView = null

var glow_layer: Node2D = null

var _region_id: int = -1

var _lit: bool = false

var _lit_elapsed: float = 0.0

var _presence_from: float = 0.0

var _fade_left: float = 0.0
var _fade_from_fill: float = 0.0
var _fade_from_glow: float = 0.0

var _fill_alpha_now: float = 0.0
var _glow_alpha_now: float = 0.0

var _fill_loops: Array[PackedVector2Array] = []
var _fill_is_hole: Array[bool] = []
var _fill_color: Color = Color.WHITE
var _hole_color: Color = Color.WHITE

var _glow_lines: Array[Line2D] = []
var _glow_material: ShaderMaterial = null


## 默认不处理每帧更新，需要显示或淡出时才开启。
func _ready() -> void:
	set_process(false)


## 切换或重新点亮区域，重建几何；同一区域淡出中重启时从当前透明度接续。
func show_region(region_id: int) -> void:
	if _lit and region_id == _region_id:
		return

	var refade_same: bool = not _lit and region_id == _region_id
	_presence_from = clampf(_fill_alpha_now / FILL_ALPHA, 0.0, 1.0) if refade_same else 0.0
	_region_id = region_id
	_lit = true
	_lit_elapsed = 0.0
	_fade_left = 0.0
	_rebuild()
	_update_lit_alpha()
	set_process(true)


## 开始淡出当前区域，保留几何直到淡出完成。
func stop() -> void:
	if not _lit:
		return
	_lit = false
	_fade_left = FADE_OUT_SEC
	_fade_from_fill = _fill_alpha_now
	_fade_from_glow = _glow_alpha_now
	if FADE_OUT_SEC <= 0.0:
		_finish_fade()


## 判断是否仍有可显示的区域，包括正在淡出的状态。
func is_showing() -> bool:
	return _lit


## 返回当前区域编号，没有区域时为 -1。
func showing_region() -> int:
	return _region_id if _lit else -1


## 按当前状态推进呼吸或淡出，结束后关闭逐帧处理。
func _process(delta: float) -> void:
	if _lit:
		_lit_elapsed += delta
		_update_lit_alpha()
		return
	_fade_left -= delta
	if _fade_left <= 0.0:
		_finish_fade()
		return
	var remain: float = _fade_left / FADE_OUT_SEC
	_fill_alpha_now = _fade_from_fill * remain
	_glow_alpha_now = _fade_from_glow * remain
	_apply_alpha()


## 结合入场淡入与周期呼吸，更新填充和发光的透明度。
func _update_lit_alpha() -> void:
	var fade_in: float = 1.0
	if FADE_IN_SEC > 0.0:
		fade_in = clampf(_lit_elapsed / FADE_IN_SEC, 0.0, 1.0)
	var presence: float = lerpf(_presence_from, 1.0, fade_in)
	_fill_alpha_now = FILL_ALPHA * presence
	_glow_alpha_now = (1.0 - cos(TAU * _lit_elapsed / BREATH_SEC)) * 0.5 * presence
	_apply_alpha()


## 清除当前区域与透明度，并停止逐帧处理。
func _finish_fade() -> void:
	_region_id = -1
	_fill_alpha_now = 0.0
	_glow_alpha_now = 0.0
	_apply_alpha()
	set_process(false)


## 请求填充重绘，同时更新全部发光线的透明度。
func _apply_alpha() -> void:
	queue_redraw()
	for line: Line2D in _glow_lines:
		line.modulate = Color(1.0, 1.0, 1.0, _glow_alpha_now)
		line.visible = _glow_alpha_now > 0.0


## 先绘制区域外轮廓填充，再用棋盘背景色覆盖内部孔洞。
func _draw() -> void:
	if _fill_alpha_now <= 0.0:
		return

	for want_hole: bool in [false, true]:
		for i in _fill_loops.size():
			if _fill_is_hole[i] == want_hole and _fill_loops[i].size() >= 3:
				var base: Color = _hole_color if want_hole else _fill_color
				draw_colored_polygon(_fill_loops[i], Color(base, base.a * _fill_alpha_now))


## 从区域格子追踪边界，完成像素转换、外扩和圆角，再同步发光线与色调。
func _rebuild() -> void:
	_fill_loops.clear()
	_fill_is_hole.clear()
	if board == null or not is_instance_valid(board) or _region_id < 0:
		_sync_glow_lines([])
		return
	var cells: Array[Vector2i] = _region_cells()
	if cells.is_empty():
		_sync_glow_lines([])
		return
	var slot_px: float = float(board.get_grid_slot())
	var origin: Vector2 = Vector2.ONE * float(board.get_grid_padding())

	var face_edge_inset: float = (slot_px - float(board.get_grid_cell_face_px())) * 0.5
	var region_color: Color = board.get_region_color(_region_id)
	_fill_color = Color(region_color, 1.0)
	_hole_color = board.get_board_background_color()
	var lattice_loops: Array[PackedVector2Array] = RegionOutlineGeometry.trace_lattice_loops(cells)
	var glow_loops: Array[PackedVector2Array] = []
	for lattice_loop: PackedVector2Array in lattice_loops:
		var square: PackedVector2Array = RegionOutlineGeometry.to_board(
			lattice_loop, origin, slot_px
		)
		var fill_square: PackedVector2Array = RegionOutlineGeometry.offset_loop(
			square, FILL_OFFSET_PX - face_edge_inset
		)
		var fill_loop: PackedVector2Array = RegionOutlineGeometry.fillet_loop(
			fill_square, _convex_radii(lattice_loop), _concave_radius()
		)
		_fill_loops.append(fill_loop)
		_fill_is_hole.append(RegionOutlineGeometry.is_hole(fill_loop))
		glow_loops.append(
			RegionOutlineGeometry.offset_loop(square, GLOW_OFFSET_PX - face_edge_inset)
		)
	_sync_glow_lines(glow_loops)
	_ensure_glow_material().set_shader_parameter(
		"glow_tint", Color.from_hsv(region_color.h, 1.0, 1.0)
	)


## 从棋盘区域图中收集当前区域的行列坐标。
func _region_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var regions: Array = board.get_regions()
	var puzzle_size: int = board.get_puzzle_size()
	for r in mini(puzzle_size, regions.size()):
		var region_row: Array = regions[r]
		for c in mini(puzzle_size, region_row.size()):
			if int(region_row[c]) == _region_id:
				cells.append(Vector2i(r, c))
	return cells


## 为边界凸角找到所属格子的圆角半径，并增加高亮外扩量。
func _convex_radii(lattice_loop: PackedVector2Array) -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	var count: int = lattice_loop.size()
	for i in count:
		var corner: Vector2 = lattice_loop[i]
		var incoming: Vector2 = (corner - lattice_loop[(i - 1 + count) % count]).normalized()
		var leaving: Vector2 = (lattice_loop[(i + 1) % count] - corner).normalized()
		if not RegionOutlineGeometry.is_convex_corner(incoming, leaving):
			radii.append(0.0)
			continue
		var at: Array[int] = RegionOutlineGeometry.convex_corner_cell(corner, incoming, leaving)
		radii.append(_cell_corner_radius(at[0], at[1], at[2]) + FILL_CONVEX_EXTRA_PX)
	return radii


## 使用区域首个格子的圆角基准计算凹角半径。
func _concave_radius() -> float:
	var cells: Array[Vector2i] = _region_cells()
	if cells.is_empty():
		return FILL_CONCAVE_EXTRA_PX
	return _cell_corner_radius(cells[0].x, cells[0].y, 0) + FILL_CONCAVE_EXTRA_PX


## 从棋盘格子视图取得指定角的实际半径。
func _cell_corner_radius(r: int, c: int, corner: int) -> float:
	var cell: CellView = board.get_cell_view(r, c)
	if cell == null:
		return 0.0
	var radii: Vector4 = cell.get_face_render_radii()
	return radii[corner]


## 复用 Line2D 池绘制每条闭合轮廓，多余节点清空点集。
func _sync_glow_lines(loops: Array[PackedVector2Array]) -> void:
	if glow_layer == null or not is_instance_valid(glow_layer):
		return
	while _glow_lines.size() < loops.size():
		var line: Line2D = Line2D.new()
		line.closed = true
		line.texture = _GLOW_TEXTURE
		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.round_precision = 8
		line.antialiased = true
		line.width = GLOW_WIDTH_PX
		line.material = _ensure_glow_material()
		glow_layer.add_child(line)
		_glow_lines.append(line)
	for i in _glow_lines.size():
		var line: Line2D = _glow_lines[i]
		line.points = loops[i] if i < loops.size() else PackedVector2Array()


## 首次使用时建立发光材质，并设置核心亮度范围。
func _ensure_glow_material() -> ShaderMaterial:
	if _glow_material == null:
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = _GLOW_TINT_SHADER
		_glow_material.set_shader_parameter("core_from", GLOW_CORE_FROM)
		_glow_material.set_shader_parameter("core_to", GLOW_CORE_TO)
	return _glow_material
