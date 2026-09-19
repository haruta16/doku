# 滑动手势保护区调试可视化：把 SwipeAxisGuard 的锁定带画成绿色半透明条
# 仅在非 release 构建里由 BoardView 创建，默认关闭，靠 cheat 命令切换
class_name SwipeZoneDebugOverlay
extends Control

# ---- 布局参数（由 BoardView 注入，与棋盘同一套像素换算） ----
var _slot: int = 0 # 单格槽位边长（像素，含间隙，= BoardView.SLOT_PX）
var _padding: int = 0 # 棋盘四周留白（像素，= BoardView.BOARD_PADDING）
var _n: int = 0 # 棋盘边长（行列数）
# ---- 运行时状态 ----
var _enabled: bool = false # 是否显示（cheat 命令 toggle_swipe_zone_viz 切换）
var _lock: Dictionary = {} # 当前锁定带 {"axis","value","tol"}，空字典表示未锁定


# 进树即设成不吃鼠标、画在最上层：只负责显示，不参与输入
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE # 鼠标事件穿透
	z_index = 100 # 画在棋盘与格子之上


# 注入棋盘布局尺寸并清空旧锁定带（BoardView._ensure_zone_viz 调用）
func configure(slot_px: int, padding: int, puzzle_size: int) -> void:
	_slot = slot_px
	_padding = padding
	_n = puzzle_size
	_lock = {}
	queue_redraw()


# 开关显示；不改变已有锁定数据
func set_enabled(on: bool) -> void:
	_enabled = on
	queue_redraw()


# 更新锁定带数据；关闭状态下只存不重绘
func set_zone(lock: Dictionary) -> void:
	_lock = lock
	if _enabled: # 只有显示中才需要重绘
		queue_redraw()


# 画锁定带：band 是含容差的外圈，core 是被锁定的那一行/列，两条绿线标出容差边界
func _draw() -> void:
	if not _enabled or _lock.is_empty(): # 未开启或无锁定带时不画
		return
	var extent: float = _padding * 2 + _slot * _n # 棋盘总边长（像素）
	var idx: int = _lock["value"] # 被锁定的行号 / 列号
	var tol: float = _lock["tol"] # 容差（像素）：核心区两侧各外扩这么多
	var core0: float = _padding + idx * _slot # 核心区起始像素
	var core1: float = _padding + (idx + 1) * _slot # 核心区结束像素
	var band0: float = core0 - tol # 容差带起始像素
	var band1: float = core1 + tol # 容差带结束像素
	# 由外到内三档绿色：容差填充 / 核心填充 / 边界线
	var fill := Color(0.1, 0.9, 0.35, 0.16)
	var core := Color(0.1, 0.9, 0.35, 0.3)
	var edge := Color(0.1, 1.0, 0.45, 0.95)
	# axis 为 ROW 表示锁住一行（画横条），否则锁住一列（画竖条）
	if _lock["axis"] == SwipeAxisGuard.Axis.ROW:
		draw_rect(Rect2(0.0, band0, extent, band1 - band0), fill) # 容差区填充
		draw_rect(Rect2(0.0, core0, extent, core1 - core0), core) # 核心区填充
		draw_line(Vector2(0.0, band0), Vector2(extent, band0), edge, 3.0) # 上边界线
		draw_line(Vector2(0.0, band1), Vector2(extent, band1), edge, 3.0) # 下边界线
	else:
		draw_rect(Rect2(band0, 0.0, band1 - band0, extent), fill) # 容差区填充
		draw_rect(Rect2(core0, 0.0, core1 - core0, extent), core) # 核心区填充
		draw_line(Vector2(band0, 0.0), Vector2(band0, extent), edge, 3.0) # 左边界线
		draw_line(Vector2(band1, 0.0), Vector2(band1, extent), edge, 3.0) # 右边界线
