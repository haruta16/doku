## 可复现题目生成：使用种子随机数先摆合法答案猫，再按不同版本扩张区域，最后用回溯计数筛唯一解。
class_name PuzzleGenerator
extends RefCounted


## 将乘法结果截断到有符号 32 位，服务于固定序列的随机数计算。
static func _imul(a: int, b: int) -> int:
	return _to_int32((a & 4294967295) * (b & 4294967295))


## 保留低 32 位，并把最高位为一的结果解释为负数。
static func _to_int32(n: int) -> int:
	n = n & 4294967295
	if n >= 2147483648:
		n -= 4294967296
	return n


## 执行一次 Mulberry32 风格的状态推进，返回新种子与 [0, 1) 浮点数。
static func _mulberry32_step(seed: int) -> Array:
	seed = _to_int32(seed + 1831565813)
	var t: int = _imul(seed ^ (seed >> 15), 1 | seed)
	t = _to_int32(t + _imul(t ^ (t >> 7), 61 | t)) ^ t
	var f: float = float((t ^ (t >> 14)) & 4294967295) / 4294967296.0
	return [seed, f]


class RNG:
	var _state: Array[int] = [0]

	## 用给定种子初始化这个随机数实例的独立状态。
	func _init(seed_val: int) -> void:
		_state[0] = seed_val

	## 推进实例随机状态并返回下一个浮点数，避免依赖全局随机序列。
	func next() -> float:
		var result: Array = PuzzleGenerator._mulberry32_step(_state[0])
		_state[0] = result[0]
		return result[1]


## 复制数组后执行 Fisher–Yates 洗牌，不改变传入数组顺序。
static func _shuffle(arr: Array, rng: RNG) -> Array:
	var a: Array = arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j: int = int(rng.next() * (i + 1))
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


## 生成连续编号数组，供随机选择列号或区域编号。
static func _range(n: int) -> Array:
	var arr: Array = []
	for i in range(n):
		arr.append(i)
	return arr


## 通过逐行回溯摆放互不冲突的猫，再把列号结果转成布尔答案矩阵。
static func _place_pieces(size: int, rng: RNG) -> Array:
	var cols: Array[int] = []
	cols.resize(size)
	cols.fill(-1)

	var placed := _place_pieces_solve(0, size, cols, rng)
	if not placed:
		cols.fill(-1)

	var grid: Array = []
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(false)
		grid.append(row)

	for r in range(size):
		if cols[r] >= 0:
			grid[r][cols[r]] = true
	return grid


## 检查候选位置是否与此前行的猫同列或八邻接，区域规则在后续生成时建立。
static func _is_valid(row: int, col: int, cols: Array[int]) -> bool:
	for r in range(row):
		var c: int = cols[r]
		if c == col:
			return false
		if abs(r - row) <= 1 and abs(c - col) <= 1:
			return false
	return true


## 每行随机排列候选列，尝试合法落点；后续无解时撤销并换列。
static func _place_pieces_solve(row: int, size: int, cols: Array[int], rng: RNG) -> bool:
	if row == size:
		return true
	var order: Array = _shuffle(_range(size), rng)
	for col in order:
		if _is_valid(row, col, cols):
			cols[row] = col
			if _place_pieces_solve(row + 1, size, cols, rng):
				return true
			cols[row] = -1
	return false


## 以每只答案猫为区域种子，随机从边界向空格扩张，剩余格最后按邻接关系补齐。
static func _generate_regions_v1(size: int, solution: Array, rng: RNG) -> Array:
	var regions: Array = []
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(-1)
		regions.append(row)

	var piece_positions: Array = []
	for r in range(size):
		for c in range(size):
			if solution[r][c]:
				piece_positions.append([r, c])

	for idx in range(piece_positions.size()):
		var rc: Array = piece_positions[idx]
		regions[rc[0]][rc[1]] = idx

	var unassigned: Dictionary = {}
	for r in range(size):
		for c in range(size):
			if regions[r][c] == -1:
				unassigned["%d,%d" % [r, c]] = true

	var dirs: Array = [[0, 1], [0, -1], [1, 0], [-1, 0]]
	var max_iter: int = size * size * 10

	while unassigned.size() > 0 and max_iter > 0:
		max_iter -= 1
		var region_order: Array = _shuffle(_range(size), rng)
		for region_idx in region_order:
			if unassigned.size() == 0:
				break
			var border_cells: Array = []
			for r in range(size):
				for c in range(size):
					if regions[r][c] != region_idx:
						continue
					for d in dirs:
						var nr: int = r + d[0]
						var nc: int = c + d[1]
						if (
							nr >= 0
							and nr < size
							and nc >= 0
							and nc < size
							and regions[nr][nc] == -1
						):
							border_cells.append([nr, nc])
			if border_cells.size() > 0:
				var pick_idx: int = int(rng.next() * border_cells.size())
				var picked: Array = border_cells[pick_idx]
				regions[picked[0]][picked[1]] = region_idx
				unassigned.erase("%d,%d" % [picked[0], picked[1]])

	for key in unassigned.keys():
		var parts: PackedStringArray = key.split(",")
		var r: int = int(parts[0])
		var c: int = int(parts[1])
		for d in dirs:
			var nr: int = r + d[0]
			var nc: int = c + d[1]
			if nr >= 0 and nr < size and nc >= 0 and nc < size and regions[nr][nc] != -1:
				regions[r][c] = regions[nr][nc]
				break
		if regions[r][c] == -1:
			regions[r][c] = 0

	return regions


## 扩张区域时为横向或纵向生长设置权重，bias 控制形状延伸偏好。
static func _generate_regions_v2(size: int, solution: Array, rng: RNG, bias: float) -> Array:
	var regions: Array = []
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(-1)
		regions.append(row)

	var pieces: Array = []
	for r in range(size):
		for c in range(size):
			if solution[r][c]:
				pieces.append([r, c])

	for i in range(pieces.size()):
		regions[pieces[i][0]][pieces[i][1]] = i

	var r_min: Array[int] = []
	var r_max: Array[int] = []
	var c_min: Array[int] = []
	var c_max: Array[int] = []
	for i in range(size):
		r_min.append(pieces[i][0])
		r_max.append(pieces[i][0])
		c_min.append(pieces[i][1])
		c_max.append(pieces[i][1])

	var order: Array = _shuffle(_range(size), rng)
	var is_h: Array[bool] = []
	is_h.resize(size)
	for i in range(size):
		is_h[order[i]] = (i % 2 == 0)

	var w_high: float = 1.0 + bias * 9.0
	var w_med: float = 1.0 + bias * 2.0
	var w_low: float = 1.0

	var unassigned: Dictionary = {}
	for r in range(size):
		for c in range(size):
			if regions[r][c] == -1:
				unassigned["%d,%d" % [r, c]] = true

	var dirs: Array = [[0, 1], [0, -1], [1, 0], [-1, 0]]
	var max_iter: int = size * size * 15

	while unassigned.size() > 0 and max_iter > 0:
		max_iter -= 1
		var reg_order: Array = _shuffle(_range(size), rng)
		for ri in reg_order:
			if unassigned.size() == 0:
				break
			var border_map: Dictionary = {}
			for r in range(size):
				for c in range(size):
					if regions[r][c] != ri:
						continue
					for d in dirs:
						var nr: int = r + d[0]
						var nc: int = c + d[1]
						if nr < 0 or nr >= size or nc < 0 or nc >= size:
							continue
						if regions[nr][nc] != -1:
							continue
						var w: float
						if is_h[ri]:
							if nr >= r_min[ri] and nr <= r_max[ri]:
								w = w_high
							elif nr == r_min[ri] - 1 or nr == r_max[ri] + 1:
								w = w_med
							else:
								w = w_low
						else:
							if nc >= c_min[ri] and nc <= c_max[ri]:
								w = w_high
							elif nc == c_min[ri] - 1 or nc == c_max[ri] + 1:
								w = w_med
							else:
								w = w_low
						var key: String = "%d,%d" % [nr, nc]
						if not border_map.has(key) or w > border_map[key]["w"]:
							border_map[key] = {"r": nr, "c": nc, "w": w}

			if border_map.size() == 0:
				continue

			var cells: Array = border_map.values()
			var total: float = 0.0
			for cell in cells:
				total += cell["w"]
			var pick: float = rng.next() * total
			var chosen: Dictionary = cells[0]
			for cell in cells:
				pick -= cell["w"]
				if pick <= 0.0:
					chosen = cell
					break

			regions[chosen["r"]][chosen["c"]] = ri
			unassigned.erase("%d,%d" % [chosen["r"], chosen["c"]])
			r_min[ri] = min(r_min[ri], chosen["r"])
			r_max[ri] = max(r_max[ri], chosen["r"])
			c_min[ri] = min(c_min[ri], chosen["c"])
			c_max[ri] = max(c_max[ri], chosen["c"])

	if unassigned.size() > 0:
		for key in unassigned.keys():
			var parts: PackedStringArray = key.split(",")
			var r: int = int(parts[0])
			var c: int = int(parts[1])
			for d in dirs:
				var nr: int = r + d[0]
				var nc: int = c + d[1]
				if nr >= 0 and nr < size and nc >= 0 and nc < size and regions[nr][nc] != -1:
					regions[r][c] = regions[nr][nc]
					break
			if regions[r][c] == -1:
				regions[r][c] = 0

	return regions


## 先围绕部分答案猫构造横纵条带，再依据条带布局扩张其余区域。
static func _generate_regions_v3(size: int, solution: Array, rng: RNG, strip_count: int) -> Array:
	var regions: Array = []
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(-1)
		regions.append(row)

	var pieces: Array = []
	for r in range(size):
		for c in range(size):
			if solution[r][c]:
				pieces.append([r, c])
	for i in range(pieces.size()):
		regions[pieces[i][0]][pieces[i][1]] = i

	var num_strips: int = max(0, min(strip_count, size - 1))
	var order: Array = _shuffle(_range(size), rng)
	var is_strip: Array = []
	is_strip.resize(size)
	is_strip.fill(true)
	var is_h: Array = []
	is_h.resize(size)
	is_h.fill(false)
	for i in range(num_strips, size):
		is_strip[order[i]] = false
	for i in range(num_strips):
		is_h[order[i]] = (i % 2 == 0)

	for ri in _shuffle(_range(size), rng):
		if not is_strip[ri]:
			continue
		var qr: int = pieces[ri][0]
		var qc: int = pieces[ri][1]
		var extra: int = 1 + int(rng.next() * min(3, size - 2))
		var added: int = 0
		if is_h[ri]:
			var left: int = qc - 1
			var right: int = qc + 1
			while added < extra:
				var go_left: bool = rng.next() < 0.5
				if go_left and left >= 0 and regions[qr][left] == -1:
					regions[qr][left] = ri
					left -= 1
					added += 1
				elif right < size and regions[qr][right] == -1:
					regions[qr][right] = ri
					right += 1
					added += 1
				elif not go_left and left >= 0 and regions[qr][left] == -1:
					regions[qr][left] = ri
					left -= 1
					added += 1
				else:
					break
		else:
			var up: int = qr - 1
			var down: int = qr + 1
			while added < extra:
				var go_up: bool = rng.next() < 0.5
				if go_up and up >= 0 and regions[up][qc] == -1:
					regions[up][qc] = ri
					up -= 1
					added += 1
				elif down < size and regions[down][qc] == -1:
					regions[down][qc] = ri
					down += 1
					added += 1
				elif not go_up and up >= 0 and regions[up][qc] == -1:
					regions[up][qc] = ri
					up -= 1
					added += 1
				else:
					break

	var dirs: Array = [[0, 1], [0, -1], [1, 0], [-1, 0]]
	var r_min: Array = []
	r_min.resize(size)
	var r_max: Array = []
	r_max.resize(size)
	var c_min: Array = []
	c_min.resize(size)
	var c_max: Array = []
	c_max.resize(size)
	for i in range(size):
		r_min[i] = pieces[i][0]
		r_max[i] = pieces[i][0]
		c_min[i] = pieces[i][1]
		c_max[i] = pieces[i][1]
	for r in range(size):
		for c in range(size):
			var ri: int = regions[r][c]
			if ri < 0:
				continue
			r_min[ri] = min(r_min[ri], r)
			r_max[ri] = max(r_max[ri], r)
			c_min[ri] = min(c_min[ri], c)
			c_max[ri] = max(c_max[ri], c)

	var blob_is_h: Array = []
	blob_is_h.resize(size)
	for i in range(size):
		blob_is_h[i] = is_h[i] if is_strip[i] else (rng.next() < 0.5)

	const W_HIGH: int = 15
	const W_MED: int = 3
	const W_LOW: int = 1

	var unassigned: Dictionary = {}
	for r in range(size):
		for c in range(size):
			if regions[r][c] == -1:
				unassigned["%d,%d" % [r, c]] = true

	var growable: Array = []
	for i in range(size):
		if not is_strip[i]:
			growable.append(i)

	var max_iter: int = size * size * 15
	while unassigned.size() > 0 and max_iter > 0:
		max_iter -= 1
		var reg_order: Array = _shuffle(growable.duplicate(), rng)
		for ri in reg_order:
			if unassigned.size() == 0:
				break
			var border_map: Dictionary = {}
			for r in range(size):
				for c in range(size):
					if regions[r][c] != ri:
						continue
					for d in dirs:
						var nr: int = r + d[0]
						var nc: int = c + d[1]
						if nr < 0 or nr >= size or nc < 0 or nc >= size:
							continue
						if regions[nr][nc] != -1:
							continue
						var w: int
						if blob_is_h[ri]:
							if nr >= r_min[ri] and nr <= r_max[ri]:
								w = W_HIGH
							elif nr == r_min[ri] - 1 or nr == r_max[ri] + 1:
								w = W_MED
							else:
								w = W_LOW
						else:
							if nc >= c_min[ri] and nc <= c_max[ri]:
								w = W_HIGH
							elif nc == c_min[ri] - 1 or nc == c_max[ri] + 1:
								w = W_MED
							else:
								w = W_LOW
						var key: String = "%d,%d" % [nr, nc]
						if not border_map.has(key) or w > border_map[key]["w"]:
							border_map[key] = {"r": nr, "c": nc, "w": w}
			if border_map.size() == 0:
				continue
			var cells: Array = border_map.values()
			var total: float = 0.0
			for cell in cells:
				total += cell["w"]
			var pick: float = rng.next() * total
			var chosen: Dictionary = cells[0]
			for cell in cells:
				pick -= cell["w"]
				if pick <= 0.0:
					chosen = cell
					break
			regions[chosen["r"]][chosen["c"]] = ri
			unassigned.erase("%d,%d" % [chosen["r"], chosen["c"]])
			r_min[ri] = min(r_min[ri], chosen["r"])
			r_max[ri] = max(r_max[ri], chosen["r"])
			c_min[ri] = min(c_min[ri], chosen["c"])
			c_max[ri] = max(c_max[ri], chosen["c"])

	if unassigned.size() > 0:
		for key in unassigned.keys():
			var parts: PackedStringArray = key.split(",")
			var r: int = int(parts[0])
			var c: int = int(parts[1])
			for d in dirs:
				var nr: int = r + d[0]
				var nc: int = c + d[1]
				if nr >= 0 and nr < size and nc >= 0 and nc < size and regions[nr][nc] != -1:
					regions[r][c] = regions[nr][nc]
					break
			if regions[r][c] == -1:
				regions[r][c] = 0

	return regions


## 先建立指定数量的条带，再优先把空格分给相邻的较小非条带区域，兼顾最小面积参数。
static func _generate_regions_v4(
	size: int, solution: Array, rng: RNG, strip_count: int, min_region_size: int
) -> Array:
	var regions: Array = []
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(-1)
		regions.append(row)
	var dirs: Array = [[0, 1], [0, -1], [1, 0], [-1, 0]]

	var pieces: Array = []
	for r in range(size):
		for c in range(size):
			if solution[r][c]:
				pieces.append([r, c])

	var region_size: Array = []
	region_size.resize(size)
	region_size.fill(1)
	for i in range(pieces.size()):
		regions[pieces[i][0]][pieces[i][1]] = i

	var strip_regs_local: Dictionary = {}
	var strip_order: Array = _shuffle(_range(size), rng)
	for i in range(min(strip_count, size)):
		var ri: int = strip_order[i]
		strip_regs_local[ri] = true
		var qr: int = pieces[ri][0]
		var qc: int = pieces[ri][1]
		var is_h: bool = i % 2 == 0
		var min_extra: int = max(1, min_region_size - 1)
		var extra: int = min(size - 2, min_extra + int(rng.next() * 3))
		var added: int = 0
		if is_h:
			var left: int = qc - 1
			var right: int = qc + 1
			while added < extra:
				if rng.next() < 0.5 and left >= 0 and regions[qr][left] == -1:
					regions[qr][left] = ri
					left -= 1
					added += 1
					region_size[ri] += 1
				elif right < size and regions[qr][right] == -1:
					regions[qr][right] = ri
					right += 1
					added += 1
					region_size[ri] += 1
				elif left >= 0 and regions[qr][left] == -1:
					regions[qr][left] = ri
					left -= 1
					added += 1
					region_size[ri] += 1
				else:
					break
		else:
			var up: int = qr - 1
			var down: int = qr + 1
			while added < extra:
				if rng.next() < 0.5 and up >= 0 and regions[up][qc] == -1:
					regions[up][qc] = ri
					up -= 1
					added += 1
					region_size[ri] += 1
				elif down < size and regions[down][qc] == -1:
					regions[down][qc] = ri
					down += 1
					added += 1
					region_size[ri] += 1
				elif up >= 0 and regions[up][qc] == -1:
					regions[up][qc] = ri
					up -= 1
					added += 1
					region_size[ri] += 1
				else:
					break

	var unassigned: int = 0
	for r in range(size):
		for c in range(size):
			if regions[r][c] == -1:
				unassigned += 1

	var max_iter: int = size * size * 15
	while unassigned > 0 and max_iter > 0:
		max_iter -= 1
		var any_assigned: bool = false
		for r in range(size):
			for c in range(size):
				if regions[r][c] != -1:
					continue
				var best_reg: int = -1
				var best_sz: int = 99999
				for d in dirs:
					var nr: int = r + d[0]
					var nc: int = c + d[1]
					if nr < 0 or nr >= size or nc < 0 or nc >= size:
						continue
					if regions[nr][nc] == -1:
						continue
					var reg: int = regions[nr][nc]
					if strip_regs_local.has(reg):
						continue
					if region_size[reg] < best_sz:
						best_sz = region_size[reg]
						best_reg = reg
				if best_reg == -1:
					for d in dirs:
						var nr: int = r + d[0]
						var nc: int = c + d[1]
						if nr < 0 or nr >= size or nc < 0 or nc >= size:
							continue
						if regions[nr][nc] == -1:
							continue
						if region_size[regions[nr][nc]] < best_sz:
							best_sz = region_size[regions[nr][nc]]
							best_reg = regions[nr][nc]
				if best_reg >= 0:
					regions[r][c] = best_reg
					region_size[best_reg] += 1
					unassigned -= 1
					any_assigned = true
		if not any_assigned:
			break

	for r in range(size):
		for c in range(size):
			if regions[r][c] == -1:
				regions[r][c] = 0

	return regions


## 复制区域后尝试转移边界格，保护答案猫、条带和最小面积，并用广度搜索检查原区域连通。
static func _perturb_regions(
	base_regions: Array,
	size: int,
	solution: Array,
	rng: RNG,
	min_region_size: int,
	strip_regs: Dictionary
) -> Array:
	var regions: Array = []
	for r in range(size):
		regions.append(base_regions[r].duplicate())
	var dirs: Array = [[0, 1], [0, -1], [1, 0], [-1, 0]]
	var region_size: Array = []
	region_size.resize(size)
	region_size.fill(0)
	for r in range(size):
		for c in range(size):
			region_size[regions[r][c]] += 1

	var queen_set: Dictionary = {}
	for r in range(size):
		for c in range(size):
			if solution[r][c]:
				queen_set["%d,%d" % [r, c]] = true

	var iterations: int = size * size * 2
	for _iter in range(iterations):
		var r: int = int(rng.next() * size)
		var c: int = int(rng.next() * size)
		if queen_set.has("%d,%d" % [r, c]):
			continue
		var cur_reg: int = regions[r][c]
		if strip_regs.has(cur_reg):
			continue
		var other_regs: Array = []
		for d in dirs:
			var nr: int = r + d[0]
			var nc: int = c + d[1]
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				var nr_reg: int = regions[nr][nc]
				if nr_reg != cur_reg and not strip_regs.has(nr_reg):
					other_regs.append(nr_reg)
		if other_regs.size() == 0:
			continue
		var target_reg: int = other_regs[int(rng.next() * other_regs.size())]
		var tn: int = 0
		for d in dirs:
			var nr2: int = r + d[0]
			var nc2: int = c + d[1]
			if (
				nr2 >= 0
				and nr2 < size
				and nc2 >= 0
				and nc2 < size
				and regions[nr2][nc2] == target_reg
			):
				tn += 1
		if tn > 1 and rng.next() > 0.3:
			continue
		if region_size[cur_reg] <= max(1, min_region_size):
			continue
		var same_nbrs: Array = []
		for d in dirs:
			var nr2: int = r + d[0]
			var nc2: int = c + d[1]
			if nr2 >= 0 and nr2 < size and nc2 >= 0 and nc2 < size and regions[nr2][nc2] == cur_reg:
				same_nbrs.append([nr2, nc2])
		if same_nbrs.size() < 2:
			continue
		regions[r][c] = -1
		var visited: Dictionary = {}
		var bfs_q: Array = [same_nbrs[0]]
		visited["%d,%d" % [same_nbrs[0][0], same_nbrs[0][1]]] = true
		while not bfs_q.is_empty():
			var cur: Array = bfs_q.pop_front()
			for d in dirs:
				var nr2: int = cur[0] + d[0]
				var nc2: int = cur[1] + d[1]
				var bkey: String = "%d,%d" % [nr2, nc2]
				if (
					nr2 >= 0
					and nr2 < size
					and nc2 >= 0
					and nc2 < size
					and regions[nr2][nc2] == cur_reg
					and not visited.has(bkey)
				):
					visited[bkey] = true
					bfs_q.append([nr2, nc2])
		var all_reachable: bool = true
		for nb in same_nbrs:
			if not visited.has("%d,%d" % [nb[0], nb[1]]):
				all_reachable = false
				break
		if not all_reachable:
			regions[r][c] = cur_reg
			continue
		regions[r][c] = target_reg
		region_size[cur_reg] -= 1
		region_size[target_reg] += 1

	return regions


## 按版本和配置分别建立答案与区域，返回尺寸、区域矩阵和布尔答案；本入口不筛唯一解。
static func generate_puzzle(config: Dictionary) -> Dictionary:
	var size: int = config["size"]
	var seed_val: int = config["seed"]
	var region_seed: int = config.get("region_seed", -1)
	var bias: float = config.get("bias", 0.0)
	var version: int = config.get("version", 0)

	var rng: RNG = RNG.new(seed_val)
	var solution: Array = _place_pieces(size, rng)

	var regions: Array
	if version == 4:
		var eff_strips: int = config.get("strip_count", size - 1)
		var v4_region_seed: int = max(0, config.get("region_seed", 0))
		var min_region_size: int = config.get("min_region_size", 0)
		var perturb_trial: int = config.get("perturb_trial", 0)
		var reg_rng: RNG = RNG.new(seed_val * 10000 + v4_region_seed)
		var base_regions: Array = _generate_regions_v4(
			size, solution, reg_rng, eff_strips, min_region_size
		)
		if perturb_trial > 0 and eff_strips < size - 1:
			var strip_regs: Dictionary = {}
			for reg in range(size):
				var rows: Dictionary = {}
				var cols: Dictionary = {}
				for r in range(size):
					for c in range(size):
						if base_regions[r][c] == reg:
							rows[r] = true
							cols[c] = true
				if rows.size() == 1 or cols.size() == 1:
					strip_regs[reg] = true
			var pert_rng: RNG = RNG.new(seed_val * 100000 + v4_region_seed * 100 + perturb_trial)
			regions = _perturb_regions(
				base_regions, size, solution, pert_rng, min_region_size, strip_regs
			)
		else:
			regions = base_regions
	elif version == 2 and region_seed >= 0:
		var reg_rng: RNG = RNG.new(region_seed)
		regions = _generate_regions_v2(size, solution, reg_rng, bias)
	elif version == 2:
		var reg_rng: RNG = RNG.new(seed_val)
		regions = _generate_regions_v2(size, solution, reg_rng, bias)
	elif version == 3:
		var v3_attempt: int = config.get("v3_attempt", 0)
		var strip_count_cfg: int = config.get("strip_count", size - 1)
		var reg_rng: RNG = RNG.new(v3_attempt)
		regions = _generate_regions_v3(size, solution, reg_rng, strip_count_cfg)
	else:
		regions = _generate_regions_v1(size, solution, rng)

	return {"size": size, "regions": regions, "solution": solution}


## 用带候选传播的回溯计数，达到 limit 即停止；默认只需区分零解、唯一解和多解。
static func count_solutions(size: int, regions: Array, limit: int = 2) -> int:
	var count: Array = [0]
	var placed: Array = []
	placed.resize(size)
	placed.fill(-1)
	var region_filled: Array = []
	region_filled.resize(size)
	region_filled.fill(false)
	var col_used: Array = []
	col_used.resize(size)
	col_used.fill(false)
	var candidates: Array = []
	for _r in range(size):
		var s: Dictionary = {}
		for ci in range(size):
			s[ci] = true
		candidates.append(s)
	_cs_solve(size, regions, placed, region_filled, col_used, candidates, count, limit)
	return count[0]


## 试放猫后原地删除同列、相邻和同区域候选，返回删除记录及是否仍有候选。
static func _cs_propagate(
	row: int, col: int, size: int, regions: Array, placed: Array, candidates: Array
) -> Array:
	var removals: Array = []
	var rid: int = regions[row][col]
	var ok: bool = true
	for r in range(size):
		if placed[r] != -1 or r == row:
			continue
		if candidates[r].has(col):
			candidates[r].erase(col)
			removals.append([r, col])
		if abs(r - row) == 1:
			for dc in range(-1, 2):
				var ac: int = col + dc
				if ac >= 0 and ac < size and candidates[r].has(ac):
					candidates[r].erase(ac)
					removals.append([r, ac])
		for ci in candidates[r].keys().duplicate():
			if regions[r][ci] == rid:
				candidates[r].erase(ci)
				removals.append([r, ci])
		if candidates[r].size() == 0:
			ok = false
			break
	return [removals, ok]


## 根据删除记录恢复候选集合，撤销一次试放造成的传播。
static func _cs_unprop(removals: Array, candidates: Array) -> void:
	for item in removals:
		candidates[item[0]][item[1]] = true


## 优先扩展候选最少的未填行，传播约束并回溯恢复，累计完整解直到上限。
static func _cs_solve(
	size: int,
	regions: Array,
	placed: Array,
	region_filled: Array,
	col_used: Array,
	candidates: Array,
	count: Array,
	limit: int
) -> void:
	if count[0] >= limit:
		return
	var best_row: int = -1
	var best_sz: int = size + 1
	for r in range(size):
		if placed[r] != -1:
			continue
		if candidates[r].size() < best_sz:
			best_sz = candidates[r].size()
			best_row = r
	if best_row == -1:
		count[0] += 1
		return
	if best_sz == 0:
		return
	for col in candidates[best_row].keys().duplicate():
		var rid: int = regions[best_row][col]
		if region_filled[rid] or col_used[col]:
			continue
		placed[best_row] = col
		col_used[col] = true
		region_filled[rid] = true
		var prop: Array = _cs_propagate(best_row, col, size, regions, placed, candidates)
		var removals: Array = prop[0]
		var ok: bool = prop[1]
		if ok:
			_cs_solve(size, regions, placed, region_filled, col_used, candidates, count, limit)
		_cs_unprop(removals, candidates)
		placed[best_row] = -1
		col_used[col] = false
		region_filled[rid] = false
		if count[0] >= limit:
			return


## 在多组答案种子和区域尝试中检查区域面积、扰动与唯一解，成功即返回，预算耗尽返回空字典。
static func generate_solvable_puzzle(config: Dictionary) -> Dictionary:
	var size: int = config["size"]
	var base_seed: int = config.get("seed", 0)
	var min_region_size: int = config.get("min_region_size", 0)
	var strip_count_raw: int = config.get("strip_count", -1)
	var max_attempts: int = config.get("max_attempts", 500)
	var effective_strips: int = (size - 1) if strip_count_raw < 0 else strip_count_raw

	@warning_ignore("integer_division")
	var num_seeds: int = min(100, max(1, max_attempts / 20))
	@warning_ignore("integer_division")
	var attempts_per_seed: int = max(10, max_attempts / num_seeds)

	for s in range(num_seeds):
		var seed_val: int = base_seed + s * 7919
		var rng: RNG = RNG.new(seed_val)
		var solution: Array = _place_pieces(size, rng)

		var strip_regs: Dictionary = {}
		var consecutive_fails: int = 0

		for attempt in range(attempts_per_seed):
			var reg_rng: RNG = RNG.new(seed_val * 10000 + attempt)
			var base_regions: Array = _generate_regions_v4(
				size, solution, reg_rng, effective_strips, min_region_size
			)

			var counts: Dictionary = {}
			for r in range(size):
				for c in range(size):
					var ri: int = base_regions[r][c]
					counts[ri] = counts.get(ri, 0) + 1
			if counts.size() != size:
				consecutive_fails += 1
				if consecutive_fails > 50:
					break
				continue

			if min_region_size > 0:
				var valid: bool = true
				for sz in counts.values():
					if sz < min_region_size:
						valid = false
						break
				if not valid:
					consecutive_fails += 1
					if consecutive_fails > 50:
						break
					continue

			consecutive_fails = 0

			strip_regs.clear()
			for reg in range(size):
				var rows: Dictionary = {}
				var cols: Dictionary = {}
				for r in range(size):
					for c in range(size):
						if base_regions[r][c] == reg:
							rows[r] = true
							cols[c] = true
				if rows.size() == 1 or cols.size() == 1:
					strip_regs[reg] = true

			var perturb_trials: int = 5 if effective_strips < size - 1 else 1
			for pt in range(perturb_trials):
				var regions: Array
				if perturb_trials > 1:
					var pert_rng: RNG = RNG.new(seed_val * 100000 + attempt * 100 + pt)
					regions = _perturb_regions(
						base_regions, size, solution, pert_rng, min_region_size, strip_regs
					)
					if min_region_size > 0:
						var pc: Dictionary = {}
						for r in range(size):
							for c in range(size):
								pc[regions[r][c]] = pc.get(regions[r][c], 0) + 1
						var valid2: bool = true
						for sz in pc.values():
							if sz < min_region_size:
								valid2 = false
								break
						if not valid2:
							continue
				else:
					regions = base_regions

				if count_solutions(size, regions, 2) != 1:
					continue

				return {"size": size, "regions": regions, "solution": solution, "seed": seed_val}

	return {}
