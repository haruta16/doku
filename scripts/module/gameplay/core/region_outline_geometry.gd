## 区域轮廓几何：从棋盘格提取有向边界环，再转换为像素坐标、偏移和圆角路径。
class_name RegionOutlineGeometry
extends RefCounted


## 用棋盘原点和格距把格点轮廓变换为绘制坐标。
static func to_board(
	lattice_loop: PackedVector2Array, origin: Vector2, slot_px: float
) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for lattice_point: Vector2 in lattice_loop:
		corners.append(origin + lattice_point * slot_px)
	return corners


## 按相邻边外法线移动直角顶点，偏移量以像素为单位。
static func offset_loop(corners: PackedVector2Array, offset_px: float) -> PackedVector2Array:
	if is_zero_approx(offset_px):
		return corners
	var shifted: PackedVector2Array = PackedVector2Array()
	var count: int = corners.size()
	for i in count:
		var incoming: Vector2 = (corners[i] - corners[(i - 1 + count) % count]).normalized()
		var leaving: Vector2 = (corners[(i + 1) % count] - corners[i]).normalized()
		shifted.append(
			corners[i] + (_outward_normal(incoming) + _outward_normal(leaving)) * offset_px
		)
	return shifted


## 分别处理凸角与凹角圆角，半径限制为相邻短边的一半，输出离散弧线。
static func fillet_loop(
	corners: PackedVector2Array, convex_radii: PackedFloat32Array, concave_radius: float
) -> PackedVector2Array:
	var count: int = corners.size()
	if count < 3:
		return corners
	var rounded: PackedVector2Array = PackedVector2Array()
	for i in count:
		var corner: Vector2 = corners[i]
		var prev_corner: Vector2 = corners[(i - 1 + count) % count]
		var next_corner: Vector2 = corners[(i + 1) % count]
		var incoming: Vector2 = (corner - prev_corner).normalized()
		var leaving: Vector2 = (next_corner - corner).normalized()
		var wanted: float = (
			convex_radii[i] if is_convex_corner(incoming, leaving) else concave_radius
		)
		var radius: float = minf(
			wanted, minf(corner.distance_to(prev_corner), corner.distance_to(next_corner)) * 0.5
		)
		if radius <= 0.0:
			rounded.append(corner)
			continue
		var arc_start: Vector2 = corner - incoming * radius
		var arc_end: Vector2 = corner + leaving * radius
		var center: Vector2 = arc_start + leaving * radius
		var start_angle: float = (arc_start - center).angle()
		var sweep: float = wrapf((arc_end - center).angle() - start_angle, -PI, PI)
		var segments: int = clampi(ceili(radius * 0.75), 2, 24)
		for step in segments + 1:
			rounded.append(
				center + Vector2.from_angle(start_angle + sweep * step / segments) * radius
			)
	return rounded


## 用入边与出边的叉积判断凸角，方向约定沿用本文件的边界追踪。
static func is_convex_corner(incoming: Vector2, leaving: Vector2) -> bool:
	return incoming.x * leaving.y - incoming.y * leaving.x > 0.0


## 依据有向面积的负号识别内部孔洞边界。
static func is_hole(loop: PackedVector2Array) -> bool:
	return signed_area(loop) < 0.0


## 用鞋带公式计算有向面积，符号保留边界绕行方向。
static func signed_area(loop: PackedVector2Array) -> float:
	var twice_area: float = 0.0
	var count: int = loop.size()
	for i in count:
		var point: Vector2 = loop[i]
		var next_point: Vector2 = loop[(i + 1) % count]
		twice_area += point.x * next_point.y - next_point.x * point.y
	return twice_area * 0.5


## 把格点凸角定位回棋盘行列和格子角编号，供局部圆角控制。
static func convex_corner_cell(
	lattice_point: Vector2, incoming: Vector2, leaving: Vector2
) -> Array[int]:
	var col: int = roundi(lattice_point.x)
	var row: int = roundi(lattice_point.y)

	var quadrant: Vector2 = leaving - incoming
	var cell_col: int = col if quadrant.x > 0.0 else col - 1
	var cell_row: int = row if quadrant.y > 0.0 else row - 1
	var corner: int = 0
	if quadrant.x > 0.0 and quadrant.y > 0.0:
		corner = 0
	elif quadrant.x < 0.0 and quadrant.y > 0.0:
		corner = 1
	elif quadrant.x < 0.0 and quadrant.y < 0.0:
		corner = 2
	else:
		corner = 3
	return [cell_row, cell_col, corner]


## 从区域格子集合提取格点坐标下的闭合边界环。
static func trace_lattice_loops(cells: Array[Vector2i]) -> Array[PackedVector2Array]:
	return _trace_boundary(cells)


## 移除相邻格子共享的内部边，再逐条消耗外边组成轮廓环。
static func _trace_boundary(cells: Array[Vector2i]) -> Array[PackedVector2Array]:
	var cell_set: Dictionary = {}
	for cell: Vector2i in cells:
		cell_set[cell] = true

	var outgoing: Dictionary = {}
	var edge_count: int = 0
	for cell: Vector2i in cells:
		var top_left: Vector2i = Vector2i(cell.y, cell.x)
		var top_right: Vector2i = top_left + Vector2i(1, 0)
		var bottom_right: Vector2i = top_left + Vector2i(1, 1)
		var bottom_left: Vector2i = top_left + Vector2i(0, 1)
		var sides: Array = [
			[Vector2i(-1, 0), top_left, top_right],
			[Vector2i(0, 1), top_right, bottom_right],
			[Vector2i(1, 0), bottom_right, bottom_left],
			[Vector2i(0, -1), bottom_left, top_left],
		]
		for side: Array in sides:
			var neighbor_offset: Vector2i = side[0]
			if cell_set.has(cell + neighbor_offset):
				continue
			var edge_start: Vector2i = side[1]
			if not outgoing.has(edge_start):
				outgoing[edge_start] = []
			var edge_ends: Array = outgoing[edge_start]
			edge_ends.append(side[2])
			edge_count += 1
	var loops: Array[PackedVector2Array] = []
	var loop_starts: Array = outgoing.keys()
	for loop_start: Vector2i in loop_starts:
		var start_ends: Array = outgoing[loop_start]
		while not start_ends.is_empty():
			loops.append(_walk_loop(outgoing, loop_start, edge_count))
	return loops


## 沿出边追踪一个环，异常断边或超限时报告并截断，最后去掉共线点。
static func _walk_loop(
	outgoing: Dictionary, loop_start: Vector2i, edge_count: int
) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([Vector2(loop_start)])
	var start_ends: Array = outgoing[loop_start]
	var current: Vector2i = start_ends.pop_back()
	var heading: Vector2i = current - loop_start
	var guard: int = edge_count
	while current != loop_start:
		guard -= 1
		if guard < 0:
			push_error("RegionOutlineGeometry: 边界环没有闭合,轮廓已截断")
			break
		points.append(Vector2(current))
		var next_point: Vector2i = _take_rightmost(outgoing, current, heading)
		if next_point == current:
			push_error("RegionOutlineGeometry: 格点 %s 没有出边,轮廓已截断" % current)
			break
		heading = next_point - current
		current = next_point
	return _drop_collinear(points)


## 优先选择当前方向右转程度最大的出边，并从待追踪集合移除。
static func _take_rightmost(outgoing: Dictionary, at: Vector2i, heading: Vector2i) -> Vector2i:
	if not outgoing.has(at):
		return at
	var edge_ends: Array = outgoing[at]
	var best_index: int = -1
	var best_turn: int = -2
	for i in edge_ends.size():
		var edge_end: Vector2i = edge_ends[i]
		var direction: Vector2i = edge_end - at
		var turn: int = heading.x * direction.y - heading.y * direction.x
		if turn > best_turn:
			best_turn = turn
			best_index = i
	if best_index < 0:
		return at
	var chosen: Vector2i = edge_ends[best_index]
	edge_ends.remove_at(best_index)
	return chosen


## 删除不改变行进方向的中间点，仅保留轮廓拐角。
static func _drop_collinear(points: PackedVector2Array) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	var count: int = points.size()
	for i in count:
		var incoming: Vector2 = (points[i] - points[(i - 1 + count) % count]).normalized()
		var leaving: Vector2 = (points[(i + 1) % count] - points[i]).normalized()
		if not incoming.is_equal_approx(leaving):
			corners.append(points[i])
	return corners


## 按边界方向计算向外的垂直向量。
static func _outward_normal(direction: Vector2) -> Vector2:
	return Vector2(direction.y, -direction.x)
