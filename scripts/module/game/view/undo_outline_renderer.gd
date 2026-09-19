# 撤销描边渲染器：把一组格子并成连通簇，算出并集轮廓，用发光带 + 黄色描边画出来并做脉冲
class_name UndoOutlineRenderer
extends Node2D

# ---- 描边与光晕参数（像素） ----
static var STROKE_WIDTH: float = 10.0 # 黄线宽度
const STROKE_COLOR: Color = Color("#FBFF00") # 描边颜色
static var GLOW_LINE_WIDTH: float = 95.0 # 光晕带宽
static var GLOW_PADDING: float = 15.0 # 轮廓外扩量，决定光晕范围
static var STROKE_PADDING: float = -3.0 # 描边轮廓的独立外扩量
static var CORNER_RADIUS_OUTER: float = 15.0 # 外轮廓圆角半径
static var CORNER_RADIUS_INNER: float = 15.0 # 内轮廓圆角半径

# ---- 运行时状态 ----
var _line_pairs: Array = [] # 每个簇一组 {wrapper, stroke, glow}
var _pulse_tween: Tween = null # 脉冲/淡出 Tween
var _cluster_cells: Array = [] # 每个簇包含的格子


# ================= 对外接口 =================
# 簇数量（供撤销执行器遍历）
func get_cluster_count() -> int:
	return _cluster_cells.size()


# 取第 i 个簇的挂载节点
func get_cluster_wrapper(i: int) -> Node2D:
	if i < _line_pairs.size():
		return _line_pairs[i]["wrapper"]
	return null


# 取第 i 个簇包含的格子
func get_cluster_cells(i: int) -> Array[Vector2i]:
	if i < _cluster_cells.size():
		return _cluster_cells[i]
	return []


# 画出这些格子的并集轮廓；cells 为空则隐藏
func show_outline(
	cells: Array[Vector2i], cell_size: int, board_padding: int, slot_px: int, cell_gap: int
) -> void:
	print("[UndoOutline] show_outline called, cells=%d" % cells.size())
	# 没有格子就不用画
	if cells.is_empty():
		hide_outline()
		return

	# 坐标集合，供轮廓算法判断邻居
	var cell_set: Dictionary = {}
	for pos: Vector2i in cells:
		cell_set[pos] = true

	# 用四邻接把格子分成连通簇
	var clusters: Array = _find_clusters(cells, cell_set)
	_cluster_cells = clusters
	print("[UndoOutline] clusters=%d" % clusters.size())

	_ensure_line_pairs(clusters.size())

	# 每个簇三条轮廓：光晕外扩轮廓、描边轮廓、光晕外边界
	var has_any: bool = false
	for i in range(clusters.size()):
		var cluster: Array[Vector2i] = clusters[i]
		var cluster_set: Dictionary = {}
		for pos: Vector2i in cluster:
			cluster_set[pos] = true
		# 光晕用简单轮廓，描边用带圆角的轮廓
		var contour_simple: PackedVector2Array = _compute_contour_simple(
			cluster, cluster_set, cell_size, board_padding, slot_px, cell_gap, GLOW_PADDING
		)
		var contour_bezier: PackedVector2Array = _compute_contour_bezier(
			cluster, cluster_set, cell_size, board_padding, slot_px, cell_gap, STROKE_PADDING
		)
		var contour_outer: PackedVector2Array = _compute_contour_simple(
			cluster,
			cluster_set,
			cell_size,
			board_padding,
			slot_px,
			cell_gap,
			GLOW_PADDING + GLOW_LINE_WIDTH * 0.5
		)
		# 轮廓算不出来就清空这个簇
		if contour_simple.is_empty():
			_line_pairs[i]["glow"].clear_points()
			_line_pairs[i]["stroke"].clear_points()
		# 写进对应的线节点并同步线宽
		else:
			_line_pairs[i]["glow"].points = contour_simple
			_line_pairs[i]["glow"].width = GLOW_LINE_WIDTH
			_update_glow_clip_polygon(_line_pairs[i]["glow"], contour_bezier)
			_update_glow_outer_clip(_line_pairs[i]["glow"], contour_outer)
			_line_pairs[i]["stroke"].points = contour_bezier
			_line_pairs[i]["stroke"].width = STROKE_WIDTH
			has_any = true

	# 多余的簇清空
	for i in range(clusters.size(), _line_pairs.size()):
		_line_pairs[i]["glow"].clear_points()
		_line_pairs[i]["stroke"].clear_points()

	# 有内容才显示并脉冲
	if has_any:
		visible = true
		_start_pulse()
		print(
			(
				"[UndoOutline] visible=true, line_pairs=%d, stroke_points=%d"
				% [
					_line_pairs.size(),
					_line_pairs[0]["stroke"].points.size() if not _line_pairs.is_empty() else 0
				]
			)
		)
	else:
		hide_outline()


# 隐藏：淡出后置为不可见
func hide_outline() -> void:
	if not visible:
		return
	_fade_out()


# ================= 内部渲染 =================
# 按需创建簇对应的节点组（wrapper + 光晕线 + 描边线）
func _ensure_line_pairs(count: int) -> void:
	# 光晕用的条纹贴图
	var tex: Texture2D = load("res://assets/sprites/game/undo_glow_strip.png")
	# 每个簇一组节点
	while _line_pairs.size() < count:
		var wrapper := Node2D.new()
		add_child(wrapper)

		# 光晕：宽白线 + 裁剪材质
		var glow := Line2D.new()
		glow.width = GLOW_LINE_WIDTH
		glow.default_color = Color.WHITE
		glow.joint_mode = Line2D.LINE_JOINT_ROUND
		glow.material = _create_glow_clip_material()
		glow.closed = true
		glow.texture_mode = Line2D.LINE_TEXTURE_TILE
		glow.texture = tex
		wrapper.add_child(glow)

		# 描边：细黄线
		var stroke := Line2D.new()
		stroke.width = STROKE_WIDTH
		stroke.default_color = STROKE_COLOR
		stroke.joint_mode = Line2D.LINE_JOINT_ROUND
		stroke.closed = true
		stroke.antialiased = true
		wrapper.add_child(stroke)

		# 记下三元组，show_outline 里按索引取用
		_line_pairs.append({"wrapper": wrapper, "stroke": stroke, "glow": glow})


# 开始脉冲：从全透明淡入
func _start_pulse() -> void:
	_stop_pulse()
	_set_lines_alpha(0.0)
	_pulse_tween = create_tween()
	# 0.067 秒淡入
	_pulse_tween.tween_method(_set_lines_alpha, 0.0, 1.0, 0.067)


# 停掉脉冲 Tween
func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null


# 淡出后置为不可见
func _fade_out() -> void:
	_stop_pulse()
	_pulse_tween = create_tween()
	# 0.067 秒淡出
	_pulse_tween.tween_method(_set_lines_alpha, 1.0, 0.0, 0.067)
	_pulse_tween.tween_callback(func() -> void: visible = false)


# 设置所有线条的透明度
func _set_lines_alpha(a: float) -> void:
	for pair in _line_pairs:
		(pair["glow"] as Line2D).modulate.a = a
		(pair["stroke"] as Line2D).modulate.a = a


# ================= 光晕材质 =================
# 生成光晕裁剪材质：用内轮廓挖空、外轮廓裁掉多余部分（GLSL 内联在下面）
func _create_glow_clip_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "\nshader_type canvas_item;\nuniform sampler2D poly_tex : filter_nearest;\nuniform int poly_count = 0;\nuniform sampler2D outer_tex : filter_nearest;\nuniform int outer_count = 0;\n\nvarying vec2 local_pos;\n\nbool point_in_polygon(vec2 p, sampler2D tex, int count) {\n\tbool inside = false;\n\tint j = count - 1;\n\tfor (int i = 0; i < count; i++) {\n\t\tvec2 vi = texelFetch(tex, ivec2(i, 0), 0).xy * 4096.0;\n\t\tvec2 vj = texelFetch(tex, ivec2(j, 0), 0).xy * 4096.0;\n\t\tif (((vi.y > p.y) != (vj.y > p.y)) &&\n\t\t\t(p.x < (vj.x - vi.x) * (p.y - vi.y) / (vj.y - vi.y) + vi.x)) {\n\t\t\tinside = !inside;\n\t\t}\n\t\tj = i;\n\t}\n\treturn inside;\n}\n\nvoid vertex() {\n\tlocal_pos = VERTEX;\n}\n\nvoid fragment() {\n\tif (point_in_polygon(local_pos, poly_tex, poly_count)) {\n\t\tdiscard;\n\t}\n\tif (outer_count > 0 && !point_in_polygon(local_pos, outer_tex, outer_count)) {\n\t\tdiscard;\n\t}\n\tCOLOR = texture(TEXTURE, UV) * COLOR;\n}\n"

	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


# 把描边轮廓写进 shader 的裁剪多边形纹理
func _update_glow_clip_polygon(glow: Line2D, clip_path: PackedVector2Array) -> void:
	var mat: ShaderMaterial = glow.material as ShaderMaterial
	if mat == null:
		return
	var count: int = clip_path.size()
	# 少于 3 个点构不成多边形，直接关掉裁剪
	if count < 3:
		mat.set_shader_parameter("poly_count", 0)
		mat.set_shader_parameter("outer_count", 0)
		return
	# 顶点坐标压进一张 RGF 纹理（除以 4096 避免超出纹理精度）
	var img := Image.create(count, 1, false, Image.FORMAT_RGF)
	for i in range(count):
		var pt: Vector2 = clip_path[i]
		img.set_pixel(i, 0, Color(pt.x / 4096.0, pt.y / 4096.0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	mat.set_shader_parameter("poly_tex", tex)
	mat.set_shader_parameter("poly_count", count)


# 把外边界轮廓写进 shader（光晕只画在这个范围内）
func _update_glow_outer_clip(glow: Line2D, outer_path: PackedVector2Array) -> void:
	var mat: ShaderMaterial = glow.material as ShaderMaterial
	if mat == null:
		return
	var count: int = outer_path.size()
	# 少于 3 个点就关掉外裁剪
	if count < 3:
		mat.set_shader_parameter("outer_count", 0)
		return
	var img := Image.create(count, 1, false, Image.FORMAT_RGF)
	for i in range(count):
		var pt: Vector2 = outer_path[i]
		img.set_pixel(i, 0, Color(pt.x / 4096.0, pt.y / 4096.0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	mat.set_shader_parameter("outer_tex", tex)
	mat.set_shader_parameter("outer_count", count)


# 备用材质：按 UV.y 阈值裁剪（当前没有调用方）
func _create_glow_shader_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "\nshader_type canvas_item;\nuniform float clip_threshold : hint_range(0.0, 1.0) = 0.7;\nvoid fragment() {\n\tvec4 tex_color = texture(TEXTURE, UV);\n\tif (UV.y > clip_threshold) {\n\t\tdiscard;\n\t}\n\tCOLOR = tex_color * COLOR;\n}\n"

	var mat := ShaderMaterial.new()
	mat.shader = shader

	var threshold: float = (
		0.5 + (GLOW_PADDING - STROKE_PADDING + STROKE_WIDTH * 0.5) / GLOW_LINE_WIDTH
	)
	mat.set_shader_parameter("clip_threshold", clampf(threshold, 0.1, 0.95))
	return mat


# 备用光晕渐变（当前没有调用方）
func _create_glow_gradient() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.add_point(0.25, Color(1, 1, 1, 0.05))
	grad.add_point(0.4, Color(1, 1, 1, 0.3))
	grad.add_point(0.5, Color(1, 1, 1, 0.7))
	grad.add_point(0.6, Color(1, 1, 1, 0.3))
	grad.add_point(0.75, Color(1, 1, 1, 0.05))
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 1
	tex.height = 64
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex


# ================= 轮廓算法 =================
# 把格子按四邻接分成连通簇（BFS），返回簇数组
func _find_clusters(cells: Array[Vector2i], cell_set: Dictionary) -> Array:
	var visited: Dictionary = {}
	# 每个格子只归一个簇
	var clusters: Array = []
	for pos: Vector2i in cells:
		if visited.has(pos):
			continue
		var cluster: Array[Vector2i] = []
		var queue: Array[Vector2i] = [pos]
		visited[pos] = true
		# 队列式 BFS，pop_front 出队保证按层扩散
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			cluster.append(cur)
			# 四个方向找邻居
			for dir: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nb: Vector2i = cur + dir
				if cell_set.has(nb) and not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		clusters.append(cluster)
	return clusters


# 用「并集的边界边」拼出有序轮廓，再按 pad 把拐点向外推（直角轮廓）
func _compute_contour_simple(
	cells: Array[Vector2i],
	cell_set: Dictionary,
	cell_size: int,
	board_padding: int,
	slot_px: int,
	_cell_gap: int,
	pad: float = 15.0
) -> PackedVector2Array:
	# 收集暴露在外的边：四邻接里没有邻居的那条
	var edges: Array = []
	for pos: Vector2i in cells:
		var r: int = pos.x
		var c: int = pos.y
		var x0: float = board_padding + c * slot_px
		var y0: float = board_padding + r * slot_px
		var x1: float = x0 + slot_px
		var y1: float = y0 + slot_px
		if not cell_set.has(Vector2i(r - 1, c)):
			edges.append([Vector2(x0, y0), Vector2(x1, y0)])
		if not cell_set.has(Vector2i(r + 1, c)):
			edges.append([Vector2(x1, y1), Vector2(x0, y1)])
		if not cell_set.has(Vector2i(r, c - 1)):
			edges.append([Vector2(x0, y1), Vector2(x0, y0)])
		if not cell_set.has(Vector2i(r, c + 1)):
			edges.append([Vector2(x1, y0), Vector2(x1, y1)])
	if edges.is_empty():
		return PackedVector2Array()
	# 把边首尾相接成环
	var ordered: Array[Vector2] = []
	var used: Array[bool] = []
	used.resize(edges.size())
	used.fill(false)
	used[0] = true
	ordered.append(edges[0][0])
	ordered.append(edges[0][1])
	# 从任意一条边出发，按端点距离贪心接龙
	for _i in range(edges.size() - 1):
		var last: Vector2 = ordered.back()
		for j in range(edges.size()):
			if used[j]:
				continue
			if (edges[j][0] as Vector2).distance_to(last) < 0.5:
				ordered.append(edges[j][1])
				used[j] = true
				break
	# 首尾重合就去掉重复点
	var n: int = ordered.size()
	if n > 2 and ordered[0].distance_to(ordered[n - 1]) < 0.5:
		n -= 1

	# 只保留拐点（方向发生变化的点）
	var corners: Array[Vector2] = []
	for i in range(n):
		var prev_idx: int = (i - 1 + n) % n
		var next_idx: int = (i + 1) % n
		var dir_in: Vector2 = (ordered[i] - ordered[prev_idx]).normalized()
		var dir_out: Vector2 = (ordered[next_idx] - ordered[i]).normalized()
		if dir_in.distance_to(dir_out) > 0.01:
			corners.append(ordered[i])

	# 拐点沿角平分线外推 pad，让轮廓包住格子
	var merged: PackedVector2Array = PackedVector2Array()
	var cn: int = corners.size()
	for i in range(cn):
		var prev_pt: Vector2 = corners[(i - 1 + cn) % cn]
		var curr: Vector2 = corners[i]
		var next_pt: Vector2 = corners[(i + 1) % cn]
		var dir_in: Vector2 = (curr - prev_pt).normalized()
		var dir_out: Vector2 = (next_pt - curr).normalized()
		var normal_in: Vector2 = Vector2(dir_in.y, -dir_in.x)
		var normal_out: Vector2 = Vector2(dir_out.y, -dir_out.x)
		var bisector: Vector2 = (normal_in + normal_out).normalized()
		merged.append(curr + bisector * pad)
	return merged


# 在简单轮廓基础上把每个角换成二次贝塞尔圆角
func _compute_contour_bezier(
	cells: Array[Vector2i],
	cell_set: Dictionary,
	cell_size: int,
	board_padding: int,
	slot_px: int,
	cell_gap: int,
	pad: float = 15.0
) -> PackedVector2Array:
	var simple: PackedVector2Array = _compute_contour_simple(
		cells, cell_set, cell_size, board_padding, slot_px, cell_gap, pad
	)
	if simple.size() < 3:
		return simple
	# 每段圆角用 32 段折线近似
	const ARC_SEGMENTS: int = 32
	var result: PackedVector2Array = PackedVector2Array()
	var cn: int = simple.size()
	print(
		(
			"[Bezier] simple_pts=%d, outer_r=%f inner_r=%f"
			% [cn, CORNER_RADIUS_OUTER, CORNER_RADIUS_INNER]
		)
	)
	# 逐个角替换成圆角
	for i in range(cn):
		var prev_pt: Vector2 = simple[(i - 1 + cn) % cn]
		var curr: Vector2 = simple[i]
		var next_pt: Vector2 = simple[(i + 1) % cn]
		var dir_in: Vector2 = (curr - prev_pt).normalized()
		var dir_out: Vector2 = (next_pt - curr).normalized()

		# 叉积判断内外角，取不同的圆角半径
		var cross: float = dir_in.x * dir_out.y - dir_in.y * dir_out.x
		var radius: float = CORNER_RADIUS_OUTER if cross < 0 else CORNER_RADIUS_INNER
		# 圆角半径不能超过相邻边长的一半
		var max_r: float = minf((curr - prev_pt).length() * 0.45, (next_pt - curr).length() * 0.45)
		var offset: float = minf(radius, max_r)
		var p1: Vector2 = curr - dir_in * offset
		var p2: Vector2 = curr + dir_out * offset
		result.append(p1)
		for seg in range(1, ARC_SEGMENTS):
			var t: float = float(seg) / float(ARC_SEGMENTS)
			var inv: float = 1.0 - t
			result.append(inv * inv * p1 + 2.0 * inv * t * curr + t * t * p2)
		result.append(p2)
	return result


# 早期的合并版轮廓算法：等于 simple + bezier 两步，但逻辑重复，当前没有调用方
func _compute_contour(
	cells: Array[Vector2i],
	cell_set: Dictionary,
	cell_size: int,
	board_padding: int,
	slot_px: int,
	_cell_gap: int
) -> PackedVector2Array:
	# 收集边界边
	var edges: Array = []
	for pos: Vector2i in cells:
		var r: int = pos.x
		var c: int = pos.y
		var x0: float = board_padding + c * slot_px
		var y0: float = board_padding + r * slot_px
		var x1: float = x0 + slot_px
		var y1: float = y0 + slot_px

		if not cell_set.has(Vector2i(r - 1, c)):
			edges.append([Vector2(x0, y0), Vector2(x1, y0)])
		if not cell_set.has(Vector2i(r + 1, c)):
			edges.append([Vector2(x1, y1), Vector2(x0, y1)])
		if not cell_set.has(Vector2i(r, c - 1)):
			edges.append([Vector2(x0, y1), Vector2(x0, y0)])
		if not cell_set.has(Vector2i(r, c + 1)):
			edges.append([Vector2(x1, y0), Vector2(x1, y1)])

	if edges.is_empty():
		return PackedVector2Array()

	# 接龙成环
	var ordered: Array[Vector2] = []
	var used: Array[bool] = []
	used.resize(edges.size())
	used.fill(false)

	used[0] = true
	ordered.append(edges[0][0])
	ordered.append(edges[0][1])

	for _i in range(edges.size() - 1):
		var last: Vector2 = ordered.back()
		var found: bool = false
		for j in range(edges.size()):
			if used[j]:
				continue
			if (edges[j][0] as Vector2).distance_to(last) < 0.5:
				ordered.append(edges[j][1])
				used[j] = true
				found = true
				break
		if not found:
			break

	if ordered.size() < 3:
		return PackedVector2Array()

	var n: int = ordered.size()
	if ordered[0].distance_to(ordered[n - 1]) < 0.5:
		n -= 1

	var merged: Array[Vector2] = []
	for i in range(n):
		var prev_idx: int = (i - 1 + n) % n
		var next_idx: int = (i + 1) % n
		var dir_in: Vector2 = (ordered[i] - ordered[prev_idx]).normalized()
		var dir_out: Vector2 = (ordered[next_idx] - ordered[i]).normalized()

		if dir_in.distance_to(dir_out) > 0.01:
			merged.append(ordered[i])

	if merged.size() < 3:
		return PackedVector2Array()

	# 圆角近似段数
	const ARC_SEGMENTS: int = 32
	var result: PackedVector2Array = PackedVector2Array()
	var mn: int = merged.size()
	for i in range(mn):
		var prev_pt: Vector2 = merged[(i - 1 + mn) % mn]
		var curr: Vector2 = merged[i]
		var next_pt: Vector2 = merged[(i + 1) % mn]

		var dir_in: Vector2 = (curr - prev_pt).normalized()
		var dir_out: Vector2 = (next_pt - curr).normalized()

		var max_offset: float = minf(
			(curr - prev_pt).length() * 0.45, (next_pt - curr).length() * 0.45
		)
		var offset: float = minf(24.0, max_offset)

		var p1: Vector2 = curr - dir_in * offset
		var p2: Vector2 = curr + dir_out * offset

		result.append(p1)

		for seg in range(1, ARC_SEGMENTS):
			var t: float = float(seg) / float(ARC_SEGMENTS)
			var inv: float = 1.0 - t
			var pt: Vector2 = inv * inv * p1 + 2.0 * inv * t * curr + t * t * p2
			result.append(pt)
		result.append(p2)

	if result.size() > 0:
		# 闭合轮廓
		result.append(result[0])

	return result
