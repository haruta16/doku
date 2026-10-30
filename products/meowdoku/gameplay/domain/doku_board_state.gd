## Doku 棋盘的唯一数据源。只保存格子值、输入锁和打叉追踪，不依赖节点或全局服务。
## 时间由调用者传入；视图、无界面规则和测试可以使用同一套状态变换。
@tool
class_name DokuBoardState
extends RefCounted

const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")
const DOUBLE_TAP_MARK_GRACE_MS: int = 1000

var _size: int = 0
var _revision: int = 0
var _cells: PackedInt32Array = PackedInt32Array()
var _input_locks: PackedByteArray = PackedByteArray()
var _ever_marked: PackedByteArray = PackedByteArray()
var _ever_errored: PackedByteArray = PackedByteArray()
var _mark_started_ms: PackedInt64Array = PackedInt64Array()
var _mark_prior_history: PackedByteArray = PackedByteArray()


func _init(size: int = 0) -> void:
	reset(size)


## 重建一盘空棋盘；负尺寸不改变现有数据。
func reset(size: int) -> bool:
	if size < 0:
		return false
	_size = size
	var count: int = size * size
	_cells.resize(count)
	_cells.fill(States.EMPTY)
	_input_locks.resize(count)
	_input_locks.fill(0)
	_ever_marked.resize(count)
	_ever_marked.fill(0)
	_ever_errored.resize(count)
	_ever_errored.fill(0)
	_mark_started_ms.resize(count)
	_mark_started_ms.fill(-1)
	_mark_prior_history.resize(count)
	_mark_prior_history.fill(0)
	_revision += 1
	return true


func get_size() -> int:
	return _size


## 棋盘值的版本；临时输入锁与表现追踪不推进此版本。
func get_revision() -> int:
	return _revision


func contains(row: int, col: int) -> bool:
	return row >= 0 and col >= 0 and row < _size and col < _size


func get_cell_state(row: int, col: int) -> int:
	return _cells[row * _size + col] if contains(row, col) else States.EMPTY


## 原始写入供恢复、演示与上层规则使用；不判断落猫是否合法，也不制造表现事件。
## 返回 true 表示值真的改变。普通操作应使用 transition_cell 保留打叉追踪。
func set_cell_state(row: int, col: int, state: int) -> bool:
	if not contains(row, col) or not _is_valid_state(state):
		return false
	var index: int = row * _size + col
	if _cells[index] == state:
		return false
	_cells[index] = state
	_revision += 1
	return true


## 保留旧 CellView.change_state 的逻辑：锁定叉不可改，草稿切换不记正式打叉历史。
## 猫能否撤回由调用用例判断；旧 BoardView 比独立 CellView 有更严格的落猫限制。
func transition_cell(row: int, col: int, state: int, at_ms: int) -> bool:
	if not contains(row, col):
		return false
	var previous: int = get_cell_state(row, col)
	if previous == States.LOCKED_MARK or not set_cell_state(row, col, state):
		return false
	if _is_draft(state) or (_is_draft(previous) and state == States.EMPTY):
		return true
	var index: int = row * _size + col
	if state == States.MARK:
		_mark_started_ms[index] = at_ms
		_mark_prior_history[index] = _ever_marked[index]
		_ever_marked[index] = 1
	else:
		if previous == States.MARK and _mark_started_ms[index] >= 0:
			if state == States.CAT and at_ms - _mark_started_ms[index] < DOUBLE_TAP_MARK_GRACE_MS:
				_ever_marked[index] = _mark_prior_history[index]
			_mark_started_ms[index] = -1
		if state == States.ERROR:
			_ever_marked[index] = 1
			_ever_errored[index] = 1
	return true


## 草稿叉转正的既有特殊语义：记录打叉时刻，但不改此前的宽容窗口快照。
func apply_draft_cross(row: int, col: int, at_ms: int) -> bool:
	if get_cell_state(row, col) != States.DRAFT_CROSS:
		return false
	if not set_cell_state(row, col, States.MARK):
		return false
	var index: int = row * _size + col
	_ever_marked[index] = 1
	_mark_started_ms[index] = at_ms
	return true


func set_input_locked(row: int, col: int, locked: bool) -> void:
	if contains(row, col):
		_input_locks[row * _size + col] = 1 if locked else 0


func is_input_locked(row: int, col: int) -> bool:
	return contains(row, col) and _input_locks[row * _size + col] != 0


func reset_cell_tracking(row: int, col: int) -> void:
	if not contains(row, col):
		return
	var index: int = row * _size + col
	_ever_marked[index] = 0
	_ever_errored[index] = 0
	_mark_started_ms[index] = -1
	_mark_prior_history[index] = 0


func has_ever_marked_x(row: int, col: int) -> bool:
	return contains(row, col) and _ever_marked[row * _size + col] != 0


func has_ever_errored(row: int, col: int) -> bool:
	return contains(row, col) and _ever_errored[row * _size + col] != 0


## 返回独立数组；调用者修改快照不会回写棋盘。
func get_board() -> Array:
	var board: Array = []
	for row in range(_size):
		var values: Array[int] = []
		for col in range(_size):
			values.append(_cells[row * _size + col])
		board.append(values)
	return board


func get_folded_board() -> Array:
	var board: Array = get_board()
	for row in range(_size):
		for col in range(_size):
			var state: int = board[row][col]
			if _is_draft(state):
				board[row][col] = States.EMPTY
			elif state == States.ERROR or state == States.LOCKED_MARK:
				board[row][col] = States.MARK
	return board


func count_state(state: int) -> int:
	return _cells.count(state)


func count_blank() -> int:
	return count_state(States.EMPTY) + count_state(States.DRAFT_CROSS) + count_state(States.DRAFT_CAT)


## 先完整校验，再一次性恢复，失败不触碰原状态。恢复会清临时输入锁和打叉时钟。
## 接受 JSON 产生的整数浮点值，拒绝截断小数、布尔值、非方阵和未知格子状态。
func restore_board(board: Array) -> bool:
	var size: int = board.size()
	var values: PackedInt32Array = PackedInt32Array()
	for row_value: Variant in board:
		if not row_value is Array:
			return false
		var row: Array = row_value
		if row.size() != size:
			return false
		for value: Variant in row:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return false
			if not is_finite(float(value)) or float(value) != floor(float(value)):
				return false
			if float(value) < States.EMPTY or float(value) > States.LOCKED_MARK:
				return false
			values.append(int(value))
	reset(size)
	_cells = values
	return true


static func _is_valid_state(state: int) -> bool:
	return state >= States.EMPTY and state <= States.LOCKED_MARK


static func _is_draft(state: int) -> bool:
	return state == States.DRAFT_CROSS or state == States.DRAFT_CAT
