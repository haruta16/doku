## 棋盘规则计算：检测同区域、同行同列和八邻接冲突，检查完成状态，并提供区域形状指标。
class_name QueendokuCore
extends RefCounted

# 违规类型：数字越小优先级越高，提示文案按这个顺序挑最该说的那条
# NONE 无冲突 / SAME_COLOR 同色区域 / SAME_LINE 同行同列 / NO_TOUCH 八邻接相贴
enum Rule { NONE = 0, SAME_COLOR = 1, SAME_LINE = 2, NO_TOUCH = 3 }


## 扫全盘：两两比较所有猫，返回 {"行,列": true} 形式的冲突格集合
static func find_conflicts(board: Array, size: int, regions: Array) -> Dictionary:
	var errors: Dictionary = {}

	# 第一步：把所有猫的坐标收集成一维列表，后面只需两两配对
	var pieces: Array[Vector2i] = []
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				pieces.append(Vector2i(r, c))

	# 第二步：任意两只猫只要同行、同列、相贴或同色，双方都算冲突
	for i in range(pieces.size()):
		for j in range(i + 1, pieces.size()):
			var a: Vector2i = pieces[i]
			var b: Vector2i = pieces[j]
			var conflict := false

			if a.x == b.x:
				conflict = true
			elif a.y == b.y:
				conflict = true
			elif abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
				conflict = true
			elif regions[a.x][a.y] == regions[b.x][b.y]:
				conflict = true

			if conflict:
				errors["%d,%d" % [a.x, a.y]] = true
				errors["%d,%d" % [b.x, b.y]] = true

	return errors


## 判定两只猫之间犯了哪条规则（供下面几个函数复用）
static func _classify_pair(a: Vector2i, b: Vector2i, regions: Array) -> int:
	if regions[a.x][a.y] == regions[b.x][b.y]:
		return Rule.SAME_COLOR
	if a.x == b.x or a.y == b.y:
		return Rule.SAME_LINE
	if abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
		return Rule.NO_TOUCH
	return Rule.NONE


## 在所有已放猫中选择优先级最高的违规类型，同色优先于同行列和相邻。
static func classify_violation(r: int, c: int, placed_cats: Array, regions: Array) -> int:
	var here := Vector2i(r, c)
	var best: int = Rule.NONE
	for cat: Vector2i in placed_cats:
		var k: int = _classify_pair(here, cat, regions)

		if k != Rule.NONE and (best == Rule.NONE or k < best):
			best = k

			if best == Rule.SAME_COLOR:
				return best
	return best


## 优先按违规类型、再按曼哈顿距离选出冲突猫；同距时偏向同行，无冲突返回 (-1, -1)。
static func find_priority_conflict_cat(
	r: int, c: int, placed_cats: Array, regions: Array
) -> Vector2i:
	var here := Vector2i(r, c)
	var not_found := Vector2i(-1, -1)
	var best := not_found
	var best_rule: int = Rule.NONE
	var best_dist: int = 0
	var best_same_row: bool = false
	for cat: Vector2i in placed_cats:
		var rule: int = _classify_pair(here, cat, regions)
		if rule == Rule.NONE:
			continue
		var d: int = absi(cat.x - r) + absi(cat.y - c)
		var same_row: bool = cat.x == r

		var better: bool = false
		if best == not_found:
			better = true
		elif rule < best_rule:
			better = true
		elif rule == best_rule:
			if d < best_dist:
				better = true
			elif d == best_dist and same_row and not best_same_row:
				better = true
		if better:
			best = cat
			best_rule = rule
			best_dist = d
			best_same_row = same_row
	return best


## 一只猫会「禁掉」哪些格子：同行、同列、八邻接、同色区域，不含自己
static func cells_excluded_by_cat(cat: Vector2i, size: int, regions: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(size):
		for c in range(size):
			if r == cat.x and c == cat.y:
				continue
			if _classify_pair(Vector2i(r, c), cat, regions) != Rule.NONE:
				out.append(Vector2i(r, c))
	return out


## 要求正式猫数量恰好等于棋盘边长，且任意两只猫均不冲突。
static func is_complete(board: Array, size: int, regions: Array) -> bool:
	var piece_count := 0
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				piece_count += 1
	if piece_count != size:
		return false
	return find_conflicts(board, size, regions).is_empty()


## 校验题库里的一条记录是否自洽：regionMap / solution 尺寸对得上、列号合法、摆出来能通关
static func validate_solution_entry(entry: Dictionary, size: int) -> bool:
	var regions: Array = entry.get("regionMap", [])
	var solution: Array = entry.get("solution", [])
	if regions.size() != size or solution.size() != size:
		return false

	# solution 每行只存一个列号，这里还原成完整棋盘
	var board: Array = []
	for r: int in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(CellState.EMPTY)
		board.append(row)
	for r: int in range(size):
		var c: int = int(solution[r])
		if c < 0 or c >= size:
			return false
		board[r][c] = CellState.CAT
	return is_complete(board, size, regions)


const DISPERSION_DENSITY_THRESHOLD: float = 0.7


## 分别计算区域格数占其最小包围矩形的比例，再对所有区域取平均。
static func compute_avg_region_bbox_fill_ratio(regions: Array) -> float:
	var stats: Dictionary = {}
	for r: int in range(regions.size()):
		var row: Array = regions[r]
		for c: int in range(row.size()):
			var rid: int = int(row[c])
			if not stats.has(rid):
				stats[rid] = {"count": 0, "min_r": r, "max_r": r, "min_c": c, "max_c": c}
			var s: Dictionary = stats[rid]
			s["count"] += 1
			s["min_r"] = min(s["min_r"], r)
			s["max_r"] = max(s["max_r"], r)
			s["min_c"] = min(s["min_c"], c)
			s["max_c"] = max(s["max_c"], c)
	if stats.is_empty():
		return 0.0
	var total_ratio: float = 0.0
	for s: Dictionary in stats.values():
		var bbox_area: int = (s["max_r"] - s["min_r"] + 1) * (s["max_c"] - s["min_c"] + 1)
		total_ratio += float(s["count"]) / float(bbox_area)
	return total_ratio / stats.size()
