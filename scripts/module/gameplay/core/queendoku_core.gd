# 游戏规则引擎：找冲突、判定违规类型、算出受影响的格子
# 9 个函数全是 static，纯数据进纯数据出，不碰节点树也不碰 UI
class_name QueendokuCore
extends RefCounted

# 违规类型：数字越小优先级越高，提示文案按这个顺序挑最该说的那条
# NONE 无冲突 / SAME_COLOR 同色区域 / SAME_LINE 同行同列 / NO_TOUCH 八邻接相贴
enum Rule { NONE = 0, SAME_COLOR = 1, SAME_LINE = 2, NO_TOUCH = 3 }


# 扫全盘：两两比较所有猫，返回 {"行,列": true} 形式的冲突格集合
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


# 判定两只猫之间犯了哪条规则（供下面几个函数复用）
static func _classify_pair(a: Vector2i, b: Vector2i, regions: Array) -> int:
	if regions[a.x][a.y] == regions[b.x][b.y]:
		return Rule.SAME_COLOR
	if a.x == b.x or a.y == b.y:
		return Rule.SAME_LINE
	if abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1:
		return Rule.NO_TOUCH
	return Rule.NONE


# 对某个格子，在已放置的猫里挑一条最该报的违规原因
static func classify_violation(r: int, c: int, placed_cats: Array, regions: Array) -> int:
	var here : Vector2i = Vector2i(r, c)
	var best: int = Rule.NONE
	for cat: Vector2i in placed_cats:
		var k: int = _classify_pair(here, cat, regions)

		# 贪心取优先级最高（数值最小）的那条
		if k != Rule.NONE and (best == Rule.NONE or k < best):
			best = k

			# SAME_COLOR 已经是最高优先级，不用再往下比
			if best == Rule.SAME_COLOR:
				return best
	return best


# 找出所有与目标格冲突的猫，用于高亮「是谁挡了你」
static func find_conflicting_cats(r: int, c: int, placed_cats: Array, regions: Array) -> Array[Vector2i]:
	var here : Vector2i = Vector2i(r, c)
	var result: Array[Vector2i] = []
	for cat: Vector2i in placed_cats:
		if _classify_pair(here, cat, regions) != Rule.NONE:
			result.append(cat)
	return result


# 一只猫会「禁掉」哪些格子：同行、同列、八邻接、同色区域，不含自己
static func cells_excluded_by_cat(cat: Vector2i, size: int, regions: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(size):
		for c in range(size):
			if r == cat.x and c == cat.y:
				continue
			if _classify_pair(Vector2i(r, c), cat, regions) != Rule.NONE:
				out.append(Vector2i(r, c))
	return out


# 同上，但按四条规则分类返回：[同行格, 同列格, 邻接格, 同色格]
# 提示系统要分别强调不同规则，所以这里不做合并
static func constraint_cells_for_cat(cat: Vector2i, size: int, regions: Array) -> Array:
	var row_cells: Array[Vector2i] = []
	var col_cells: Array[Vector2i] = []
	var nbr_cells: Array[Vector2i] = []
	var reg_cells: Array[Vector2i] = []
	var cat_region: int = int(regions[cat.x][cat.y])
	for r in range(size):
		for c in range(size):
			if r == cat.x and c == cat.y:
				continue
			var p : Vector2i = Vector2i(r, c)
			if r == cat.x:
				row_cells.append(p)
			if c == cat.y:
				col_cells.append(p)
			if abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1:
				nbr_cells.append(p)
			if int(regions[r][c]) == cat_region:
				reg_cells.append(p)
	return [row_cells, col_cells, nbr_cells, reg_cells]


# 没有颜色区域（regions）的玩法下，一只猫禁掉的格子：同行、同列、八邻接
static func cells_excluded_by_cat_no_region(cat: Vector2i, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(size):
		for c in range(size):
			if r == cat.x and c == cat.y:
				continue
			if r == cat.x or c == cat.y or (abs(r - cat.x) <= 1 and abs(c - cat.y) <= 1):
				out.append(Vector2i(r, c))
	return out


# 是否通关：猫的数量正好等于棋盘边长，且全盘无冲突
static func is_complete(board: Array, size: int, regions: Array) -> bool:
	var piece_count : int = 0
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				piece_count += 1
	if piece_count != size:
		return false
	return find_conflicts(board, size, regions).is_empty()


# 校验题库里的一条记录是否自洽：regionMap / solution 尺寸对得上、列号合法、摆出来能通关
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
