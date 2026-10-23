## 排行榜名次变动的纯布局状态；用动画进度计算行偏移、玩家位置和临时显示名次。
## 不直接操作节点，因而列表滚出再重建时仍能从同一状态恢复正确位置。

class_name RankChangeListState
extends RefCounted

const ROW_HEIGHT: float = 200.0
var player_local_y: float = 0.0
var player_replaced: bool = false
var _row_count: int = 0
var _player_slot: int = -1
var _player_rank: int = 0
var _was_unranked: bool = false
var _first: int = 0
var _last: int = -1
var _step: float = 1.0
var _drop: float = 1.0
var _progress: float = 1.0
var _start_y: float = 0.0
var _final_y: float = 0.0


func configure(row_count: int, player_slot: int, player_rank: int, was_unranked: bool) -> void:
	_row_count = maxi(0, row_count)
	_player_slot = player_slot
	_player_rank = player_rank
	_was_unranked = was_unranked
	_first = 0
	_last = -1
	_progress = 1.0
	player_replaced = false
	player_local_y = maxf(0.0, player_slot * ROW_HEIGHT)
	_start_y = player_local_y
	_final_y = player_local_y


## 确定被跨过的行区间以及玩家起终点，返回演出所需几何参数，不创建 Tween 或节点。
func prepare_rise(advance: int, drop_ratio: float) -> Dictionary:
	if _player_slot < 0 or _player_slot >= _row_count or advance <= 0:
		return {}
	var effective: int = mini(advance, _row_count - 1 - _player_slot)
	if effective <= 0:
		return {}
	_first = _player_slot + 1
	_last = _player_slot + effective
	_step = 1.0 / effective
	_drop = _step * maxf(0.01, drop_ratio)
	_final_y = _player_slot * ROW_HEIGHT
	_start_y = _final_y + effective * ROW_HEIGHT
	_progress = 0.0
	player_local_y = _start_y
	player_replaced = true
	return {
		"kind": "rise",
		"advance": effective,
		"player_slot": _player_slot,
		"player_base_y": _final_y,
		"row_h": ROW_HEIGHT,
		"cell_h": 180.0
	}


func prepare_flyout(old_rank: int, drop_ratio: float, flyout_distance: float) -> Dictionary:
	if _row_count <= 0:
		return {}
	var slots: int = clampi(old_rank - 4, 0, _row_count - 1)
	_first = 0
	_last = slots
	_step = 1.0 / (slots + 1)
	_drop = _step * maxf(0.01, drop_ratio)
	if slots == 0:
		_drop = minf(1.0, ROW_HEIGHT / maxf(1.0, flyout_distance) * maxf(0.01, drop_ratio))
	_final_y = 0.0
	_start_y = slots * ROW_HEIGHT
	_progress = 0.0
	player_local_y = _start_y
	return {
		"kind": "flyout",
		"slots": slots,
		"start_local": _start_y,
		"row_h": ROW_HEIGHT,
		"cell_h": 180.0
	}


## 接受归一化动画进度并更新玩家位置；各行偏移通过相同状态计算，保持列表一致。
func tick(progress: float) -> int:
	_progress = clampf(progress, 0.0, 1.0)
	player_local_y = lerpf(_start_y, _final_y, _progress)
	var total: int = maxi(0, _last - _first + 1)
	if _progress >= 1.0:
		return total
	if _progress < _drop:
		return 0
	return clampi(int(floor((_progress - _drop) / _step)) + 1, 0, total)


func finish() -> void:
	_progress = 1.0
	player_local_y = _final_y
	player_replaced = false


## 根据当前上升阶段计算某一行的位移，滚出后重建的行仍能得到正确偏移。
func get_row_offset(index: int) -> float:
	if index < _first or index > _last:
		return 0.0
	var start: float = (_last - index) * _step
	var end: float = minf(1.0, start + _drop)
	var local_progress: float = clampf((_progress - start) / maxf(1e-05, end - start), 0.0, 1.0)
	return -ROW_HEIGHT * (1.0 - local_progress)


func get_shown_rank(index: int, final_rank: int) -> int:
	if index < _first or index > _last:
		return final_rank
	var end: float = minf(1.0, (_last - index) * _step + _drop)
	return final_rank if _progress >= end else final_rank - 1
