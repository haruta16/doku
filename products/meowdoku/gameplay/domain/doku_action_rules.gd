## Doku 普通输入、草稿和自动动作的纯规则。只读传入值，返回计划，不访问节点或全局服务。
## 页面可以按原动画顺序执行计划；批量动作的检查点由产品层决定，不等于每格写盘。
class_name DokuActionRules
extends RefCounted

const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")
const Rules = preload("res://products/meowdoku/gameplay/domain/queendoku_core.gd")
const Board = preload("res://products/meowdoku/gameplay/domain/doku_board_state.gd")


static func tap(state: int, draft: bool) -> Dictionary:
	if draft:
		if not States.is_blank(state):
			return {"allowed": false}
		return {"allowed": true, "target": States.DRAFT_CROSS if state == States.EMPTY else States.EMPTY, "before": state, "pending": false}
	if state in [States.CAT, States.ERROR, States.LOCKED_MARK]:
		return {"allowed": false, "pending": state == States.CAT, "target": States.EMPTY}
	return {"allowed": true, "target": States.MARK if States.is_blank(state) else States.EMPTY, "before": States.EMPTY if States.is_blank(state) else state, "pending": false}


static func swipe(state: int, draft: bool, target: int, pending: bool) -> Dictionary:
	if draft:
		if not States.is_blank(state) or state == States.DRAFT_CAT or target not in [States.EMPTY, States.DRAFT_CROSS]:
			return {"allowed": false}
	else:
		if state in [States.CAT, States.ERROR, States.LOCKED_MARK]:
			return {"allowed": false}
		if pending:
			target = States.MARK if States.is_blank(state) else States.EMPTY
		if target not in [States.EMPTY, States.MARK]:
			return {"allowed": false}
	return {"allowed": state != target, "target": target, "before": state, "pending": false}


static func draft_double_tap(state: int) -> Dictionary:
	return {"allowed": States.is_blank(state), "target": States.EMPTY if state == States.DRAFT_CAT else States.DRAFT_CAT}


static func is_solution_cell(solution: Array, row: int, col: int) -> bool:
	return row >= 0 and row < solution.size() and solution[row] is Array and col >= 0 and col < solution[row].size() and bool(solution[row][col])


## 错猜先表现为普通叉，错误动画再切为 ERROR；无界面调用者可直接应用 final_state。
static func guess(board: Array, solution: Array, row: int, col: int, lives: int) -> Dictionary:
	if not _contains(board, row, col) or lives <= 0:
		return {"ok": false, "error": "round_not_playable"}
	var before: int = int(board[row][col])
	if before in [States.CAT, States.ERROR, States.LOCKED_MARK]:
		return {"ok": false, "error": "cell_not_editable"}
	var correct: bool = is_solution_cell(solution, row, col)
	return {"ok": true, "correct": correct, "before": before, "after": States.CAT if correct else States.MARK,
		"final_state": States.CAT if correct else States.ERROR, "lives": lives if correct else maxi(lives - 1, 0)}


static func lose_lives(lives: int, mistakes: int) -> Dictionary:
	var lost: int = mini(maxi(lives, 0), maxi(mistakes, 0))
	return {"lives": maxi(lives - lost, 0), "lost": lost, "last_heart": lives - 1}


static func has_wrong_guess(board: Array, history: Array = []) -> bool:
	for row: Array in board:
		if row.has(States.ERROR):
			return true
	for step: Dictionary in history:
		if bool(step.get("wrong", false)):
			return true
	return false


static func draft_marks(board: Array) -> Dictionary:
	var marks: Dictionary = {}
	for row in range(board.size()):
		for col in range(board[row].size()):
			if int(board[row][col]) in [States.DRAFT_CAT, States.DRAFT_CROSS]:
				marks[Vector2i(row, col)] = int(board[row][col])
	return marks


static func solution_fully_placed(board: Array, solution: Array) -> bool:
	var total: int = 0
	for row in range(board.size()):
		for col in range(board[row].size()):
			if is_solution_cell(solution, row, col):
				total += 1
				if board[row][col] != States.CAT:
					return false
	return total > 0


static func draft_all_correct(board: Array, solution: Array) -> bool:
	var real: int = 0
	var drafts: int = 0
	for row in range(board.size()):
		for col in range(board[row].size()):
			if board[row][col] == States.CAT:
				real += 1
			elif board[row][col] == States.DRAFT_CAT:
				if not is_solution_cell(solution, row, col):
					return false
				drafts += 1
	return real + drafts == board.size() and drafts > 0


static func draft_contradiction(board: Array, regions: Array) -> bool:
	var model: Board = Board.new()
	if not model.restore_board(board) or regions.size() != board.size() or board.is_empty():
		return false
	var merged: Array = model.get_folded_board()
	var marks: Dictionary = draft_marks(board)
	for cell: Vector2i in marks:
		merged[cell.x][cell.y] = States.CAT if marks[cell] == States.DRAFT_CAT else States.MARK
	if not Rules.find_conflicts(merged, board.size(), regions).is_empty():
		return true
	var possible_regions: Dictionary = {}
	var all_regions: Dictionary = {}
	for row in range(board.size()):
		var possible_row: bool = false
		var possible_col: bool = false
		for col in range(board.size()):
			possible_row = possible_row or merged[row][col] in [States.EMPTY, States.CAT]
			possible_col = possible_col or merged[col][row] in [States.EMPTY, States.CAT]
			var region: int = int(regions[row][col])
			all_regions[region] = true
			if merged[row][col] in [States.EMPTY, States.CAT]:
				possible_regions[region] = true
		if not possible_row or not possible_col:
			return true
	return possible_regions.size() != all_regions.size()


## 包含顺序、真假猫、统一扣命和最终盘面。UI 不再自行判断草稿答案。
static func commit_draft(board: Array, solution: Array, lives: int, lives_inf: bool = false) -> Dictionary:
	var next: Array = board.duplicate(true)
	var changes: Array = []
	var wrong: Array[Vector2i] = []
	var cells: Array = draft_marks(board).keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y - a.x < b.y - b.x if a.y - a.x != b.y - b.x else a.x > b.x)
	var wrong_candidates: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if int(board[cell.x][cell.y]) == States.DRAFT_CAT and not is_solution_cell(solution, cell.x, cell.y):
			wrong_candidates.append(cell)
	if not lives_inf and not wrong_candidates.is_empty() and wrong_candidates.size() >= lives:
		for cell: Vector2i in cells:
			next[cell.x][cell.y] = States.EMPTY
		var shown: Array[Vector2i] = wrong_candidates.slice(0, maxi(lives, 1))
		for cell: Vector2i in shown:
			next[cell.x][cell.y] = States.ERROR
		for cell: Vector2i in cells:
			changes.append({"row": cell.x, "col": cell.y, "before": board[cell.x][cell.y], "after": next[cell.x][cell.y]})
		return {"ok": true, "board": next, "changes": changes, "wrong_positions": shown, "lethal": true,
			"lives": 0, "lost": true, "last_heart": false, "has_cat": false, "has_cross": false,
			"all_correct": false, "solution_complete": false}
	var has_cat: bool = false
	var has_cross: bool = false
	for cell: Vector2i in cells:
		var before: int = int(board[cell.x][cell.y])
		var correct: bool = before == States.DRAFT_CAT and is_solution_cell(solution, cell.x, cell.y)
		var after: int = States.CAT if correct else States.MARK
		var failed: bool = before == States.DRAFT_CAT and not correct
		changes.append({"row": cell.x, "col": cell.y, "before": before, "after": States.ERROR if failed else after, "wrong": failed})
		next[cell.x][cell.y] = States.ERROR if failed else after
		if failed:
			wrong.append(cell)
		has_cat = has_cat or correct
		has_cross = has_cross or before == States.DRAFT_CROSS
	var life: Dictionary = lose_lives(lives, 0 if lives_inf else wrong.size())
	return {"ok": true, "board": next, "changes": changes, "wrong_positions": wrong,
		"lives": life.lives, "lost": life.lost, "last_heart": life.last_heart,
		"has_cat": has_cat, "has_cross": has_cross, "all_correct": draft_all_correct(board, solution),
		"solution_complete": solution_fully_placed(next, solution)}


static func clear_draft(board: Array, keep: bool = false) -> Dictionary:
	var next: Array = board.duplicate(true)
	var changes: Array = []
	if not keep:
		for cell: Vector2i in draft_marks(board):
			changes.append({"row": cell.x, "col": cell.y, "before": board[cell.x][cell.y], "after": States.EMPTY})
			next[cell.x][cell.y] = States.EMPTY
	return {"ok": true, "board": next, "changes": changes}


## 阶段与坐标顺序是可测试的动作计划；等待时长由表现层决定。
static func auto_complete(board: Array, solution: Array, include_marks: bool) -> Dictionary:
	var marks: Array[Vector2i] = []
	var cats: Array[Vector2i] = []
	var next: Array = board.duplicate(true)
	var size: int = board.size()
	for row in range(size):
		for col in range(size):
			if is_solution_cell(solution, row, col):
				if board[row][col] != States.CAT:
					cats.append(Vector2i(row, col))
					next[row][col] = States.CAT
			elif include_marks and States.is_blank(int(board[row][col])):
				marks.append(Vector2i(row, col))
				next[row][col] = States.MARK
	var by_diagonal: Callable = func(a: Vector2i, b: Vector2i) -> bool: return a.y - a.x < b.y - b.x
	marks.sort_custom(by_diagonal)
	cats.sort_custom(by_diagonal)
	return {"ok": true, "board": next, "marks": marks, "cats": cats}


static func can_offer_auto_complete(board: Array, enabled: bool, had_error: bool) -> bool:
	if not enabled or had_error or board.size() < 6:
		return false
	var cats: int = 0
	for row: Array in board:
		cats += row.count(States.CAT)
	return cats == board.size() - 1


static func auto_marks(board: Array, regions: Array, cat: Vector2i, include_region: bool) -> Array[Vector2i]:
	var excluded: Array[Vector2i] = Rules.cells_excluded_by_cat(cat, board.size(), regions) if include_region else Rules.cells_excluded_by_cat_no_region(cat, board.size())
	var result: Array[Vector2i] = []
	for cell: Vector2i in excluded:
		if board[cell.x][cell.y] == States.EMPTY:
			result.append(cell)
	return result


static func lock_sets(board: Array, regions: Array) -> Array:
	var qualified: Array = []
	for row in range(board.size()):
		for col in range(board.size()):
			if board[row][col] != States.CAT:
				continue
			var cat := Vector2i(row, col)
			var sets: Array = Rules.constraint_cells_for_cat(cat, board.size(), regions)
			for index in range(sets.size()):
				var marks: Array[Vector2i] = []
				var all_cross: bool = true
				for cell: Vector2i in sets[index]:
					if not States.is_cross(int(board[cell.x][cell.y])):
						all_cross = false
						break
					if board[cell.x][cell.y] == States.MARK:
						marks.append(cell)
				if all_cross and not marks.is_empty():
					qualified.append({"set_type": index, "cat": cat, "marks": marks})
	return qualified


static func axis_targets(board: Array, axis: int, index: int, erase: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if axis not in [0, 1] or index < 0 or index >= board.size():
		return result
	for offset in range(board.size()):
		var cell := Vector2i(offset, index) if axis == 1 else Vector2i(index, offset)
		if board[cell.x][cell.y] == (States.MARK if erase else States.EMPTY):
			result.append(cell)
	if erase:
		result.reverse()
	return result


static func life_plus_eligible(board: Array, regions: Array, row: int, col: int, lives: int, enabled: bool, used: bool, daily: bool, elapsed: float, minimum: float, first: bool, random_value: float) -> bool:
	if not enabled or used or daily or lives != 1 or elapsed <= minimum or not _contains(board, row, col) or regions.size() != board.size():
		return false
	if board[row][col] != States.CAT:
		return false
	var cats: int = 0
	var non_mark: int = 0
	var region: int = int(regions[row][col])
	for rr in range(board.size()):
		for cc in range(board.size()):
			var value: int = int(board[rr][cc])
			cats += 1 if value == States.CAT else 0
			if int(regions[rr][cc]) == region and value not in [States.MARK, States.ERROR, States.LOCKED_MARK]:
				non_mark += 1
	return cats < board.size() and non_mark == 2 and (first or random_value < 0.5)


static func _contains(board: Array, row: int, col: int) -> bool:
	return row >= 0 and row < board.size() and board[row] is Array and col >= 0 and col < board[row].size()


## 双击覆盖上一单击时，只合并同一格的单格历史；返回决定，不修改调用方历史。
static func prior_tap(last_cells: Array, row: int, col: int, fallback: int) -> Dictionary:
	if last_cells.size() == 1 and last_cells[0] is Array and last_cells[0].size() == 4:
		var cell: Array = last_cells[0]
		if int(cell[0]) == row and int(cell[1]) == col:
			return {"consume": true, "before": int(cell[2])}
	return {"consume": false, "before": fallback}
