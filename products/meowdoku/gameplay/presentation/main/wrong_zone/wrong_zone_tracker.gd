## 区域错标跟踪：记录区域被叉满的状态、补回时机和提示消费情况，支持残局保存。
class_name WrongZoneTracker
extends RefCounted

const CROSS_RATIO_THRESHOLD: float = 0.8

var _full_order: Array[int] = []

var _ever_full: Array[int] = []

var _first_full_pending: Dictionary = {}

var _hinted: Array[int] = []

var _rewarded: Array[int] = []

var _forfeited: Array[int] = []

var _refill_pending: Dictionary = {}


static func is_region_fully_crossed(board: Array, regions: Array, region_id: int) -> bool:
	var found_cell: bool = false
	for r in regions.size():
		var region_row: Array = regions[r]
		if r >= board.size():
			return false
		var board_row: Array = board[r]
		for c in region_row.size():
			if int(region_row[c]) != region_id:
				continue
			if c >= board_row.size() or not CellState.is_cross(int(board_row[c])):
				return false
			found_cell = true
	return found_cell


static func cross_ratio(board: Array, board_size: int) -> float:
	var denominator: int = board_size * board_size - board_size
	if denominator <= 0:
		return 0.0
	var cross_count: int = 0
	for r in mini(board_size, board.size()):
		var board_row: Array = board[r]
		for c in mini(board_size, board_row.size()):
			if CellState.is_cross(int(board_row[c])):
				cross_count += 1
	return float(cross_count) / float(denominator)


static func meets_cross_ratio(board: Array, board_size: int) -> bool:
	return cross_ratio(board, board_size) >= CROSS_RATIO_THRESHOLD


func reset() -> void:
	restore_state({})


func export_state() -> Dictionary:
	return {
		"full_order": _full_order.duplicate(),
		"ever_full": _ever_full.duplicate(),
		"hinted": _hinted.duplicate(),
		"rewarded": _rewarded.duplicate(),
		"forfeited": _forfeited.duplicate(),
	}


func restore_state(data: Dictionary) -> void:
	_full_order = _int_array(data.get("full_order", []))
	_ever_full = _int_array(data.get("ever_full", []))
	_hinted = _int_array(data.get("hinted", []))
	_rewarded = _int_array(data.get("rewarded", []))
	_forfeited = _int_array(data.get("forfeited", []))
	_refill_pending.clear()
	_first_full_pending.clear()


func update_region(
	region_id: int,
	fully_crossed: bool,
	is_replay: bool = false,
	cell: Vector2i = Vector2i(-1, -1),
	placed_cat: bool = false
) -> bool:
	if not is_replay:
		_settle_refill_pending(cell, placed_cat)
		_settle_first_full_pending(cell, placed_cat)
	if not fully_crossed:
		if not is_replay:
			_full_order.erase(region_id)
		return false
	if not _full_order.has(region_id):
		_full_order.append(region_id)

		if (
			not is_replay
			and _hinted.has(region_id)
			and not _rewarded.has(region_id)
			and not _forfeited.has(region_id)
		):
			if cell.x < 0:
				_forfeited.append(region_id)
			else:
				_refill_pending[region_id] = cell
	if _ever_full.has(region_id):
		return false
	if not is_replay and cell.x >= 0:
		_first_full_pending[region_id] = cell
	else:
		_ever_full.append(region_id)
	return true


func _settle_refill_pending(cell: Vector2i, placed_cat: bool) -> void:
	if _refill_pending.is_empty():
		return
	var pending_regions: Array = _refill_pending.keys()
	for region_id: int in pending_regions:
		var refill_cell: Vector2i = _refill_pending[region_id]
		if placed_cat and refill_cell == cell:
			continue
		if not _forfeited.has(region_id):
			_forfeited.append(region_id)
	_refill_pending.clear()


func _settle_first_full_pending(cell: Vector2i, placed_cat: bool) -> void:
	if _first_full_pending.is_empty():
		return
	var pending_regions: Array = _first_full_pending.keys()
	for region_id: int in pending_regions:
		var first_full_cell: Vector2i = _first_full_pending[region_id]
		if placed_cat and first_full_cell == cell:
			continue
		if not _ever_full.has(region_id):
			_ever_full.append(region_id)
	_first_full_pending.clear()


func pick_highlight_target() -> int:
	for i in range(_full_order.size() - 1, -1, -1):
		var region_id: int = _full_order[i]
		if not _hinted.has(region_id):
			return region_id
	return -1


func mark_hinted(region_id: int) -> void:
	if not _hinted.has(region_id):
		_hinted.append(region_id)
	if _first_full_pending.has(region_id):
		_first_full_pending.erase(region_id)
		if not _ever_full.has(region_id):
			_ever_full.append(region_id)


func is_hinted(region_id: int) -> bool:
	return _hinted.has(region_id)


func was_ever_full(region_id: int) -> bool:
	return _ever_full.has(region_id)


func try_reward_good_eye(region_id: int, requires_hint: bool) -> bool:
	if not _ever_full.has(region_id) or _rewarded.has(region_id):
		return false
	if requires_hint and (not _hinted.has(region_id) or _forfeited.has(region_id)):
		return false
	_rewarded.append(region_id)
	return true


func ever_full_regions() -> Array[int]:
	return _ever_full.duplicate()


func full_regions() -> Array[int]:
	return _full_order.duplicate()


static func _int_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if not (raw is Array):
		return out
	var items: Array = raw
	for item: Variant in items:
		var region_id: int = int(item)
		if not out.has(region_id):
			out.append(region_id)
	return out
