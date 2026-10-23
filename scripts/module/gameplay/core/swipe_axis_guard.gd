## 滑动轴保护：连续覆盖同一行列达到阈值后锁轴，结合像素容差与目标区域保护决定何时转向。
## 本类输入与输出的格子坐标采用 (列, 行)，与棋盘数据使用的 [行][列] 顺序不同。
class_name SwipeAxisGuard
extends RefCounted

# 锁定轴：NONE 未锁定 / ROW 锁在某一横行（只认左右滑）/ COL 锁在某一竖列（只认上下滑）
enum Axis { NONE, ROW, COL }

# ---- 棋盘几何（每次 begin 时由调用方写入） ----
var _n: int = 0 # 棋盘边长（每边几格）
var _slot: int = 0 # 相邻格子的像素步长（格宽 + 间隙）
var _padding: int = 0 # 棋盘左上角相对控件的像素偏移
var _cell: int = 0 # 单格内容区像素；当前只记录，未参与坐标换算

# ---- 开关与容差 ----
var _active: bool = false # 是否允许启用轴锁定，由识别器按 AB 配置与棋盘大小决定
var _threshold: int = 4 # 判定锁定所需的连滑格数；configure 时被夹到 >= 2

var _tol_px: float = 0.0 # 锁定后允许的垂直越界像素，超出即解锁；0.0 表示毫不容忍

var _tc_enabled: bool = false

var _tc_tol_px: float = 0.0

var _tc_can_paint: Callable = Callable()

var _regions: Array = []

# ---- 运行时状态：当前锁定 + 连滑窗口 + 上一格 ----
var _axis: int = Axis.NONE # 当前锁定的轴
var _lock_value: int = -1 # 锁定的行号（ROW）或列号（COL）；-1 表示未锁定
var _run_axis: int = Axis.NONE # 正在累积的连滑方向
var _run_value: int = -1 # 连滑所在的行号或列号
var _run_count: int = 0 # 连滑区间覆盖的格数（区间长度，不是步数）
var _run_min: int = 0 # 连滑区间的最小格序号
var _run_max: int = 0 # 连滑区间的最大格序号
var _last_cell: Vector2i = Vector2i(-1, -1) # 上一帧所在格；盘外为 (-1,-1)

const _TC_UNSET: int = -2
const _TC_DEAD: int = -1
var _tc_region: int = _TC_UNSET

var _tc_seed_cell: Vector2i = Vector2i(-1, -1)


## 记录本次手势的棋盘几何与起点，清空上次轴锁及目标区域状态；启用配置随后注入。
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

	_tc_enabled = false
	_tc_region = _TC_UNSET
	_tc_seed_cell = start_cell
	_regions = []
	_tc_can_paint = Callable()


## 写入配置：是否启用轴锁定、连滑阈值、像素容差
func configure(active: bool, threshold: int, tolerance_px: float) -> void:
	_active = active
	_threshold = maxi(2, threshold) # 阈值下限 2，避免一格抖动就上锁
	_tol_px = tolerance_px # 容差像素 = 配置里的百分比 × 格宽，由调用方算好传进来


## 拖拽中途只改启用标志（玩家在草稿/已有标记上空滑时会被关掉）
func set_active(active: bool) -> void:
	_active = active


## 注入同色保护容差、可绘制回调和区域表，并用起点建立目标区域。
func configure_target_color(
	enabled: bool, tol_px: float, can_paint: Callable, regions: Array
) -> void:
	_tc_enabled = enabled
	_tc_tol_px = maxf(0.0, tol_px)
	_tc_can_paint = can_paint
	_regions = regions

	_feed_target_color(_tc_seed_cell)


## 结束手势，清除轴锁、连续滑动窗口和目标区域记录。
func end() -> void:
	_axis = Axis.NONE
	_lock_value = -1
	_run_axis = Axis.NONE
	_run_count = 0
	_last_cell = Vector2i(-1, -1)

	_tc_region = _TC_UNSET
	_tc_seed_cell = Vector2i(-1, -1)


## 输出当前轴锁与容差信息；启用同色保护时附带目标区域，未锁轴返回空字典。
func get_debug_lock() -> Dictionary:
	if _axis == Axis.NONE:
		return {}
	var lock_info: Dictionary = {"axis": _axis, "value": _lock_value, "tol": _tol_px}
	if _tc_enabled:
		lock_info["target_color_protection"] = true
		lock_info["target_region"] = _tc_region
		lock_info["target_tol"] = _tc_tol_px
	return lock_info


## 未锁轴时累计连滑覆盖区间，达到阈值后锁定；已锁轴时交给锁定分支处理。
func process(px: float, py: float) -> Vector2i:
	if _axis != Axis.NONE:
		return _process_locked(px, py)
	var nc: Vector2i = _raw_cell(px, py)
	if nc.x < 0:
		return nc
	if nc != _last_cell:
		_advance_run(nc)

		_feed_target_color(nc)
		_last_cell = nc
		if _active and _run_count >= _threshold and _run_axis != Axis.NONE:
			_axis = _run_axis
			_lock_value = _run_value
	return nc


# ================= 内部实现 =================
## 像素 → 格子坐标 (列, 行)；盘外或尚未 begin 时返回 (-1,-1)
func _raw_cell(px: float, py: float) -> Vector2i:
	if _n == 0: # 还没 begin，几何未知
		return Vector2i(-1, -1)
	var col: int = int((px - _padding) / _slot) # 按步长整除得到列、行序号
	var row: int = int((py - _padding) / _slot)
	if row < 0 or row >= _n or col < 0 or col >= _n: # 越界一律回盘外哨兵值
		return Vector2i(-1, -1)
	return Vector2i(col, row)


## 用新格子和上一格比较，更新连滑方向、所在行/列与覆盖区间
func _advance_run(nc: Vector2i) -> void:
	var last := _last_cell
	if last.x < 0: # 上一格在盘外（刚滑进盘），重新起一段连滑
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
		return
	var same_row: bool = nc.y == last.y and nc.x != last.x # 横向移动：行不变、列变了
	var same_col: bool = nc.x == last.x and nc.y != last.y # 纵向移动：列不变、行变了
	var step_axis: int = Axis.NONE
	var step_value: int = -1
	if same_row: # 先判断这一步属于哪个轴
		step_axis = Axis.ROW
		step_value = nc.y
	elif same_col:
		step_axis = Axis.COL
		step_value = nc.x
	if step_axis == Axis.NONE: # 斜着跨格（行列同时变）不算连滑，重新起段
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
		return

	var nc_idx: int = nc.x if step_axis == Axis.ROW else nc.y # 这一步在新轴上的格序号
	if step_axis == _run_axis and step_value == _run_value: # 方向没变：撑大区间，格数按区间长度算（来回滑不重复计数）
		_run_min = mini(_run_min, nc_idx)
		_run_max = maxi(_run_max, nc_idx)
		_run_count = _run_max - _run_min + 1
	else: # 换了轴或换了行/列：以上一格和新格重开一段
		_run_axis = step_axis
		_run_value = step_value
		var last_idx: int = last.x if step_axis == Axis.ROW else last.y
		_run_min = mini(last_idx, nc_idx)
		_run_max = maxi(last_idx, nc_idx)
		_run_count = _run_max - _run_min + 1


## 将位置投影到锁定行或列，越过适用容差且允许转向时解除锁定。
func _process_locked(px: float, py: float) -> Vector2i:
	if not _active:
		return _release(px, py)
	if _axis == Axis.ROW:
		if _should_release_on_overshoot(_overshoot_1d(py, _lock_value), px, py):
			return _release(px, py)
		var col: int = clampi(int((px - _padding) / _slot), 0, _n - 1)

		var row_locked_cell := Vector2i(col, _lock_value)
		_feed_target_color(row_locked_cell)
		return row_locked_cell
	else:
		if _should_release_on_overshoot(_overshoot_1d(px, _lock_value), px, py):
			return _release(px, py)
		var row: int = clampi(int((py - _padding) / _slot), 0, _n - 1)
		var col_locked_cell := Vector2i(_lock_value, row)
		_feed_target_color(col_locked_cell)
		return col_locked_cell


## 普通模式只比较越界像素，同色保护模式还检查目标区域容差和目标格可绘制性。
func _should_release_on_overshoot(over: float, px: float, py: float) -> bool:
	if not _tc_enabled:
		return over > _tol_px

	if over <= 0.0:
		return false
	var probe: Vector2i = _raw_cell(px, py)
	if over <= _effective_tol_for(probe):
		return false
	return _tc_unlock_allowed(probe)


## 仍在初始目标区域内时使用同色容差，其他位置使用普通轴锁容差。
func _effective_tol_for(cell: Vector2i) -> float:
	if not _tc_enabled or _tc_region < 0:
		return _tol_px
	return _tc_tol_px if _region_at(cell) == _tc_region else _tol_px


## 同色保护时禁止解锁到盘外；有效回调存在时，还要求目标格可以绘制。
func _tc_unlock_allowed(probe: Vector2i) -> bool:
	if not _tc_enabled:
		return true
	if probe.x < 0:
		return false
	if not _tc_can_paint.is_valid():
		return true
	return _tc_can_paint.call(probe)


## 记住首次经过的区域，之后一旦跨区就把同色持续状态标为失效。
func _feed_target_color(cell: Vector2i) -> void:
	if not _tc_enabled or _tc_region == _TC_DEAD:
		return
	var rid: int = _region_at(cell)
	if rid < 0:
		return
	if _tc_region == _TC_UNSET:
		_tc_region = rid
	elif _tc_region != rid:
		_tc_region = _TC_DEAD


## 按 (列, 行) 坐标读取区域编号，盘外或区域数据缺失返回 -1。
func _region_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or _regions.is_empty():
		return -1
	if cell.y >= _regions.size():
		return -1
	var row: Array = _regions[cell.y]
	if cell.x >= row.size():
		return -1
	return int(row[cell.x])


## 一维越界量：返回值超出该格 [起点, 终点] 区间的像素，落在区间内为 0.0
func _overshoot_1d(v: float, idx: int) -> float:
	var lo: float = _padding + idx * _slot
	var hi: float = _padding + (idx + 1) * _slot
	if v < lo:
		return lo - v
	if v > hi:
		return v - hi
	return 0.0


## 解除轴锁后以转折点重建垂直方向的连滑窗口，并重新累计目标区域状态。
func _release(px: float, py: float) -> Vector2i:
	var prev_axis: int = _axis
	var prev_lock: int = _lock_value
	_axis = Axis.NONE
	_lock_value = -1
	var nc: Vector2i = _raw_cell(px, py)
	_last_cell = nc

	_tc_region = _TC_UNSET

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

		var corner: Vector2i = (
			Vector2i(nc.x, prev_lock) if prev_axis == Axis.ROW else Vector2i(prev_lock, nc.y)
		)
		_feed_target_color(corner)
		_feed_target_color(nc)
	else:
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
		_feed_target_color(nc)
	return nc
