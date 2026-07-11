class_name SwipeAxisGuard
extends RefCounted

enum Axis { NONE, ROW, COL }

var _n: int = 0
var _slot: int = 0
var _padding: int = 0
var _cell: int = 0

var _active: bool = false
var _threshold: int = 4
var _tol_px: float = 0.0

var _axis: int = Axis.NONE
var _lock_value: int = -1
var _run_axis: int = Axis.NONE
var _run_value: int = -1
var _run_count: int = 0
var _run_min: int = 0
var _run_max: int = 0
var _last_cell: Vector2i = Vector2i(-1, -1)


func begin(
	puzzle_size: int, slot_px: int, padding: int, cell_px: int, start_cell: Vector2i
) -> void:
	_n = puzzle_size
	_slot = slot_px
	_padding = padding
	_cell = cell_px
	_axis = Axis.NONE
	_lock_value = -1
	_run_axis = Axis.NONE
	_run_value = -1
	_last_cell = start_cell
	_run_count = 1 if start_cell.x >= 0 else 0

	_active = false


func configure(active: bool, threshold: int, tolerance_px: float) -> void:
	_active = active
	_threshold = maxi(2, threshold)
	_tol_px = tolerance_px


func set_active(active: bool) -> void:
	_active = active


func end() -> void:
	_axis = Axis.NONE
	_lock_value = -1
	_run_axis = Axis.NONE
	_run_count = 0
	_last_cell = Vector2i(-1, -1)


func get_debug_lock() -> Dictionary:
	if _axis == Axis.NONE:
		return {}
	return {"axis": _axis, "value": _lock_value, "tol": _tol_px}


func process(px: float, py: float) -> Vector2i:
	if _axis != Axis.NONE:
		return _process_locked(px, py)
	var nc: Vector2i = _raw_cell(px, py)
	if nc.x < 0:
		return nc
	if nc != _last_cell:
		_advance_run(nc)
		_last_cell = nc
		if _active and _run_count >= _threshold and _run_axis != Axis.NONE:
			_axis = _run_axis
			_lock_value = _run_value
	return nc


func _raw_cell(px: float, py: float) -> Vector2i:
	if _n == 0:
		return Vector2i(-1, -1)
	var col: int = int((px - _padding) / _slot)
	var row: int = int((py - _padding) / _slot)
	if row < 0 or row >= _n or col < 0 or col >= _n:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func _advance_run(nc: Vector2i) -> void:
	var last := _last_cell
	if last.x < 0:
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
		return
	var same_row: bool = nc.y == last.y and nc.x != last.x
	var same_col: bool = nc.x == last.x and nc.y != last.y
	var step_axis: int = Axis.NONE
	var step_value: int = -1
	if same_row:
		step_axis = Axis.ROW
		step_value = nc.y
	elif same_col:
		step_axis = Axis.COL
		step_value = nc.x
	if step_axis == Axis.NONE:
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
		return

	var nc_idx: int = nc.x if step_axis == Axis.ROW else nc.y
	if step_axis == _run_axis and step_value == _run_value:
		_run_min = mini(_run_min, nc_idx)
		_run_max = maxi(_run_max, nc_idx)
		_run_count = _run_max - _run_min + 1
	else:
		_run_axis = step_axis
		_run_value = step_value
		var last_idx: int = last.x if step_axis == Axis.ROW else last.y
		_run_min = mini(last_idx, nc_idx)
		_run_max = maxi(last_idx, nc_idx)
		_run_count = _run_max - _run_min + 1


func _process_locked(px: float, py: float) -> Vector2i:
	if _axis == Axis.ROW:
		if _overshoot_1d(py, _lock_value) > _tol_px:
			return _release(px, py)
		var col: int = clampi(int((px - _padding) / _slot), 0, _n - 1)
		return Vector2i(col, _lock_value)
	else:
		if _overshoot_1d(px, _lock_value) > _tol_px:
			return _release(px, py)
		var row: int = clampi(int((py - _padding) / _slot), 0, _n - 1)
		return Vector2i(_lock_value, row)


func _overshoot_1d(v: float, idx: int) -> float:
	var lo: float = _padding + idx * _slot
	var hi: float = _padding + (idx + 1) * _slot
	if v < lo:
		return lo - v
	if v > hi:
		return v - hi
	return 0.0


func _release(px: float, py: float) -> Vector2i:
	var prev_axis: int = _axis
	var prev_lock: int = _lock_value
	_axis = Axis.NONE
	_lock_value = -1
	var nc: Vector2i = _raw_cell(px, py)
	_last_cell = nc

	if nc.x >= 0 and prev_axis != Axis.NONE:
		if prev_axis == Axis.ROW:
			_run_axis = Axis.COL
			_run_value = nc.x
			_run_min = mini(prev_lock, nc.y)
			_run_max = maxi(prev_lock, nc.y)
		else:
			_run_axis = Axis.ROW
			_run_value = nc.y
			_run_min = mini(prev_lock, nc.x)
			_run_max = maxi(prev_lock, nc.x)
		_run_count = _run_max - _run_min + 1
	else:
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
	return nc
