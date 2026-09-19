# 滑动轴判定：指针像素 → 格子坐标，并在同轴连滑够格数后锁死该轴，防止手指抖动串到别的行/列
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

# ---- 运行时状态：当前锁定 + 连滑窗口 + 上一格 ----
var _axis: int = Axis.NONE # 当前锁定的轴
var _lock_value: int = -1 # 锁定的行号（ROW）或列号（COL）；-1 表示未锁定
var _run_axis: int = Axis.NONE # 正在累积的连滑方向
var _run_value: int = -1 # 连滑所在的行号或列号
var _run_count: int = 0 # 连滑区间覆盖的格数（区间长度，不是步数）
var _run_min: int = 0 # 连滑区间的最小格序号
var _run_max: int = 0 # 连滑区间的最大格序号
var _last_cell: Vector2i = Vector2i(-1, -1) # 上一帧所在格；盘外为 (-1,-1)


# ================= 对外接口（由 SwipeGuardRecognizer 调用） =================
# 开始一次拖拽：记录棋盘几何并清空锁定/连滑状态
func begin(
	puzzle_size: int, slot_px: int, padding: int, cell_px: int, start_cell: Vector2i
) -> void:
	_n = puzzle_size # 把本次拖拽要用的几何参数全部落下来
	_slot = slot_px
	_padding = padding
	_cell = cell_px
	_axis = Axis.NONE
	_lock_value = -1
	_run_axis = Axis.NONE
	_run_value = -1
	_last_cell = start_cell
	_run_count = 1 if start_cell.x >= 0 else 0

	_active = false # 是否启用锁定由 configure 决定，这里先关掉


# 写入配置：是否启用轴锁定、连滑阈值、像素容差
func configure(active: bool, threshold: int, tolerance_px: float) -> void:
	_active = active
	_threshold = maxi(2, threshold) # 阈值下限 2，避免一格抖动就上锁
	_tol_px = tolerance_px # 容差像素 = 配置里的百分比 × 格宽，由调用方算好传进来


# 拖拽中途只改启用标志（玩家在草稿/已有标记上空滑时会被关掉）
func set_active(active: bool) -> void:
	_active = active


# 拖拽结束：清空锁定与连滑窗口，等下次 begin 重新开始
func end() -> void:
	_axis = Axis.NONE
	_lock_value = -1
	_run_axis = Axis.NONE
	_run_count = 0
	_last_cell = Vector2i(-1, -1)


# 给调试浮层用的锁定快照 {axis, value, tol}；未锁定时返回空字典
func get_debug_lock() -> Dictionary:
	if _axis == Axis.NONE:
		return {}
	return {"axis": _axis, "value": _lock_value, "tol": _tol_px}


# 主入口：返回指针所在格子；已锁定走 _process_locked，否则按真实格推进连滑，够阈值就上锁
func process(px: float, py: float) -> Vector2i:
	if _axis != Axis.NONE: # 已锁定：只认锁定轴上的移动
		return _process_locked(px, py)
	var nc: Vector2i = _raw_cell(px, py) # 未锁定：按真实坐标算格子
	if nc.x < 0: # 指针在盘外，原样返回 (-1,-1) 让上层忽略
		return nc
	if nc != _last_cell: # 换了格子才推进连滑；同一格内抖动不计数
		_advance_run(nc)
		_last_cell = nc
		if _active and _run_count >= _threshold and _run_axis != Axis.NONE: # 启用且连滑达标 → 用当前连滑方向上锁
			_axis = _run_axis
			_lock_value = _run_value
	return nc


# ================= 内部实现 =================
# 像素 → 格子坐标 (列, 行)；盘外或尚未 begin 时返回 (-1,-1)
func _raw_cell(px: float, py: float) -> Vector2i:
	if _n == 0: # 还没 begin，几何未知
		return Vector2i(-1, -1)
	var col: int = int((px - _padding) / _slot) # 按步长整除得到列、行序号
	var row: int = int((py - _padding) / _slot)
	if row < 0 or row >= _n or col < 0 or col >= _n: # 越界一律回盘外哨兵值
		return Vector2i(-1, -1)
	return Vector2i(col, row)


# 用新格子和上一格比较，更新连滑方向、所在行/列与覆盖区间
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


# 锁定态：只允许沿锁定轴移动；垂直方向越界超过容差就解锁
func _process_locked(px: float, py: float) -> Vector2i:
	if _axis == Axis.ROW: # 锁在某行：查纵向越界，横向列号夹在盘内
		if _overshoot_1d(py, _lock_value) > _tol_px:
			return _release(px, py)
		var col: int = clampi(int((px - _padding) / _slot), 0, _n - 1)
		return Vector2i(col, _lock_value)
	else: # 锁在某列：查横向越界，纵向行号夹在盘内
		if _overshoot_1d(px, _lock_value) > _tol_px:
			return _release(px, py)
		var row: int = clampi(int((py - _padding) / _slot), 0, _n - 1)
		return Vector2i(_lock_value, row)


# 一维越界量：返回值超出该格 [起点, 终点] 区间的像素，落在区间内为 0.0
func _overshoot_1d(v: float, idx: int) -> float:
	var lo: float = _padding + idx * _slot
	var hi: float = _padding + (idx + 1) * _slot
	if v < lo:
		return lo - v
	if v > hi:
		return v - hi
	return 0.0


# 解锁：按当前真实格子重开连滑，并把连滑方向翻到另一轴——刚才垂直越界的那段算作新轴上的进度
func _release(px: float, py: float) -> Vector2i:
	var prev_axis: int = _axis # 先记下解锁前的锁定轴与锁定行/列
	var prev_lock: int = _lock_value
	_axis = Axis.NONE
	_lock_value = -1
	var nc: Vector2i = _raw_cell(px, py)
	_last_cell = nc

	if nc.x >= 0 and prev_axis != Axis.NONE: # 人还在盘内：从锁定行/列滑到当前位置的这段计入新方向
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
	else: # 已经滑出盘外：连滑窗口清零
		_run_axis = Axis.NONE
		_run_value = -1
		_run_count = 1
	return nc
