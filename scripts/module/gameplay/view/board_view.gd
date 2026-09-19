# 棋盘视图：格子节点矩阵 + 坐标换算 + 对外查询接口，是棋盘状态的唯一真源
# 上层（base_game_page / game_page）只能通过 set_cell_state() 改格子、get_board() 读全盘，
# 每次真实改动都会发 cell_state_changed，各功能模块据此记账与联动
@tool
class_name BoardView
extends Control

# ---- 布局常量（像素） ----
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn") # 单个格子场景（cell.tscn，内含 CellView）
# 自动打叉按钮场景（编辑器预览与实战共用）
const _AUTO_MARK_BTN_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/auto_mark_btn.tscn"
)
const BOARD_PADDING: int = 15 # 棋盘四周留白（像素）
const CELL_PX: int = 100 # 格子边长（像素，不含间隙）
const CELL_GAP: int = 4 # 格子间隙（像素）
const SLOT_PX: int = CELL_PX + 2 * CELL_GAP # 单格槽位 = 边长 + 两侧间隙（像素）

const BOARD_BG_CORNER_RADIUS: int = 30 # 棋盘底色圆角半径（设计值，绘制时按缩放补偿）

# ---- 自动打叉按钮尺寸（像素） ----
const _AUTO_MARK_BTN_W: float = 25.0 # 按钮宽（像素）
const _AUTO_MARK_BTN_H: float = 20.0 # 按钮高（像素）
const _AUTO_MARK_BTN_OUT_GAP: float = 25.0 # 按钮到棋盘外缘的距离（像素）

# ---- 改动来源：随 cell_state_changed 一起发出，上层据此区分对待 ----
# USER_ACTION 玩家操作 / RESTORE 恢复 / LOCATE 定位 / HINT 提示 / UNDO 撤销
# AUTOMARK 自动打叉 / PREFILL 预填 / AUTO_COMPLETE 自动完成 / DRAFT_APPLY 草稿转正
enum ChangeSource {
	USER_ACTION, RESTORE, LOCATE, HINT, UNDO, AUTOMARK, PREFILL, AUTO_COMPLETE, DRAFT_APPLY
}


# 静态算棋盘理论尺寸（像素）；布局与编辑器预览用它算居中偏移
static func intrinsic_size_for(sz: int) -> Vector2:
	var n: int = SLOT_PX * sz + BOARD_PADDING * 2
	return Vector2(n, n)


# ---- 棋盘数据（由 setup 注入） ----
var _puzzle_size: int = 0 # 棋盘边长；0 表示还没初始化
var _regions: Array = [] # 区域表 regions[行][列] = 区域号
var _color_map: Array[int] = [] # 区域号 → 调色板下标
var _region_colors: PackedColorArray = PackedColorArray() # 本次使用的区域调色板
var _cells: Array = [] # 格子节点二维数组 _cells[行][列]（视图层真源）

# ---- 提示与最近落猫（视觉状态） ----
var _hint_unit_cells: Array[Vector2i] = [] # 当前高亮的提示格
var _hint_key_cell: Vector2i = Vector2i(-1, -1) # 提示关键格（仅记录，本文件内未再读）
var _last_cat_cell: Vector2i = Vector2i(-1, -1) # 最近一次落猫的格子，通关回放时给它开粒子
var _coord_visible: bool = false # 行列坐标数字是否显示
var _coord_labels: Array[Label] = [] # 坐标 Label 列表（列在前、行在后）

# ---- 行列自动打叉按钮 ----
var _row_auto_mark_btns: Array = [] # 每行一个按钮（旋转 90°，贴棋盘右侧）
var _col_auto_mark_btns: Array = [] # 每列一个按钮（贴棋盘上方）

# ---- 编辑器预览开关（@export，仅编辑器生效；打开后用 9x9 题库第 1 关铺预览） ----
@export var editor_preview: bool = false:
	set(value):
		editor_preview = value
		if not Engine.is_editor_hint() or not is_node_ready():
			return
		if value:
			_render_editor_preview()
		else:
			_clear_editor_preview()

@export var preview_auto_mark_btns: bool = false:
	set(value):
		preview_auto_mark_btns = value
		if not Engine.is_editor_hint() or not is_node_ready():
			return

		_rebuild_auto_mark_btns()

# ---- 运行时状态 ----
var _board_bg_style: StyleBoxFlat = null # 棋盘底色样式（_draw 里画圆角矩形）

var _dragging: bool = false # 是否处于拖拽中（用来筛选移动事件）

var _swipe_viz_on: bool = false # 保护区可视化是否打开（cheat 命令切换）
var _zone_viz: SwipeZoneDebugOverlay = null # 保护区可视化节点（仅非 release 构建创建）

# ---- 对外信号 ----
signal cell_drag_start(pos: Vector2) # 拖拽开始（本地坐标）
signal cell_drag_over(pos: Vector2) # 拖拽经过（本地坐标）
signal cell_drag_end # 拖拽结束

signal cell_state_changed(row: int, col: int, state: int, source: int) # 格子状态真实变化才发（cur != state），上层据此记账 / 联动

signal axis_auto_mark_pressed(axis: int, idx: int, is_marked_before: bool) # 行列自动打叉按钮被按（axis 0=行 1=列）


# ================= 生命周期 =================
# 建棋盘底色样式；编辑器里按需铺预览，运行时读一次坐标显示设置
func _ready() -> void:
	_board_bg_style = StyleBoxFlat.new() # 白色底，圆角在 _draw 里按缩放补偿
	_board_bg_style.bg_color = Color(1, 1, 1, 1)

	if Engine.is_editor_hint():
		if editor_preview:
			_render_editor_preview()
		return
	_coord_visible = GameState.coords_visible # 坐标显示状态存在 GameState，跨局保留


# ================= 调色板 =================
# 解析区域调色板：默认取 cell.tscn 里 CellView.region_colors，命中 AB 时换实验色板
static func resolve_region_palette() -> PackedColorArray:
	var temp_cell: CellView = _CELL_SCENE.instantiate() as CellView # 临时实例只为读导出属性，读完立即 free
	var pal: PackedColorArray = temp_cell.region_colors
	temp_cell.free() # 编辑器里永远用默认色板，预览才稳定

	if Engine.is_editor_hint():
		return pal
	if ABTestManager.region_color.is_custom_palette(): # AB：自定义色板
		return PackedColorArray(
			[
				Color("#CBCB24"),
				Color("#E45F8A"),
				Color("#8D7AEB"),
				Color("#F4A2E4"),
				Color("#FF8E3D"),
				Color("#F4D27B"),
				Color("#4B7FC0"),
				Color("#A2C7ED"),
				Color("#0AAECF"),
				Color("#0DA875"),
				Color("#88CE7A"),
				Color("#AA7146"),
			]
		)
	if ABTestManager.region_color.is_new_cell_only_palette(): # AB：只有新格子用新版色板
		return PackedColorArray(
			[
				Color("#CDA400"),
				Color("#D36F8F"),
				Color("#8979DA"),
				Color("#F89BE5"),
				Color("#FA9D5C"),
				Color("#FBD983"),
				Color("#5076A5"),
				Color("#A5C6E7"),
				Color("#38A9C0"),
				Color("#2A8C53"),
				Color("#8BD57D"),
				Color("#A86D4A"),
			]
		)
	if ABTestManager.region_color.is_cell_color_v3(): # AB：cell color v3
		return PackedColorArray(
			[
				Color("#c9b35b"),
				Color("#d37291"),
				Color("#8175bf"),
				Color("#efa2e0"),
				Color("#f2a269"),
				Color("#f0cf7e"),
				Color("#5580b4"),
				Color("#a4c5e7"),
				Color("#4db5ca"),
				Color("#3fa068"),
				Color("#a1d388"),
				Color("#b07959"),
			]
		)
	return pal # 未命中任何 AB 分支，用默认色板


# ================= 初始化与布局 =================
# 铺满 size×size 格子：复用场景里已有的 Cell_r_c、注入区域色、重建坐标与打叉按钮
func setup(
	puzzle_size: int,
	regions: Array,
	color_map: Array[int],
	pattern_regions: Array = [],
	recycle_reused: bool = false
) -> void:
	_puzzle_size = puzzle_size # 棋盘边长
	_regions = regions # 区域表
	_color_map = color_map # 区域号 → 色板下标

	_dragging = false # 新局重置拖拽态

	_hint_unit_cells = [] # 清提示
	_hint_key_cell = Vector2i(-1, -1)
	_last_cat_cell = Vector2i(-1, -1) # 清上次落猫记录

	_region_colors = resolve_region_palette() # 本次使用的调色板

	var _ed: bool = Engine.is_editor_hint() # 编辑器预览不读 AB

	if not _ed and ABTestManager.region_color.is_cell_color_v3(): # AB：cell color v3 时按 RGB 重算色下标
		_color_map = (
			LevelGenerator
			. compute_color_map_for_rgb(
				puzzle_size,
				regions,
				[
					[201, 179, 91],
					[211, 114, 145],
					[129, 117, 191],
					[239, 162, 224],
					[242, 162, 105],
					[240, 207, 126],
					[85, 128, 180],
					[164, 197, 231],
					[77, 181, 202],
					[63, 160, 104],
					[161, 211, 136],
					[176, 121, 89],
				]
			)
		)
	elif not _ed and ABTestManager.region_color.is_new_cell_recompute(): # AB：新格子重算色板
		_region_colors = PackedColorArray(
			[
				Color("#CDA400"),
				Color("#D36F8F"),
				Color("#8979DA"),
				Color("#F89BE5"),
				Color("#FA9D5C"),
				Color("#FBD983"),
				Color("#5076A5"),
				Color("#A5C6E7"),
				Color("#38A9C0"),
				Color("#2A8C53"),
				Color("#8BD57D"),
				Color("#A86D4A"),
			]
		)
		_color_map = (
			LevelGenerator
			. compute_color_map_for_rgb(
				puzzle_size,
				regions,
				[
					[205, 164, 0],
					[211, 111, 143],
					[137, 121, 218],
					[248, 155, 229],
					[250, 157, 92],
					[251, 217, 131],
					[80, 118, 165],
					[165, 198, 231],
					[56, 169, 192],
					[42, 140, 83],
					[139, 213, 125],
					[168, 109, 74],
				]
			)
		)
	elif not _ed and ABTestManager.region_color.is_palette_v5(): # AB：palette v5
		_region_colors = PackedColorArray(
			[
				Color("#ac7147"),
				Color("#f19e80"),
				Color("#c36a8a"),
				Color("#afb4d2"),
				Color("#c58ced"),
				Color("#a4d987"),
				Color("#6584b3"),
				Color("#e4bc4a"),
				Color("#fea3e9"),
				Color("#4bb5b1"),
				Color("#de7e34"),
				Color("#89c4e6"),
			]
		)
		var _rgb_v5: Array = [
			[172, 113, 71],
			[241, 158, 128],
			[195, 106, 138],
			[175, 180, 210],
			[197, 140, 237],
			[164, 217, 135],
			[101, 132, 179],
			[228, 188, 74],
			[254, 163, 233],
			[75, 181, 177],
			[222, 126, 52],
			[137, 196, 230],
		]
		# 有 pattern 时走带图案的算法，否则走普通算法
		_color_map = (
			LevelGenerator.compute_color_map_for_rgb_with_pattern(
				puzzle_size, regions, _rgb_v5, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_rgb(puzzle_size, regions, _rgb_v5)
		)
	elif not _ed and ABTestManager.region_color.is_palette_v6(): # AB：palette v6
		_region_colors = PackedColorArray(
			[
				Color("#c9a779"),
				Color("#ca6666"),
				Color("#686dbf"),
				Color("#9684ec"),
				Color("#ca7849"),
				Color("#4aba34"),
				Color("#9de1e3"),
				Color("#4cabdb"),
				Color("#dc5599"),
				Color("#f4a4e7"),
				Color("#7ee388"),
				Color("#dbbc48"),
			]
		)
		var _rgb_v6: Array = [
			[201, 167, 121],
			[202, 102, 102],
			[104, 109, 191],
			[150, 132, 236],
			[202, 120, 73],
			[74, 186, 52],
			[157, 225, 227],
			[76, 171, 219],
			[220, 85, 153],
			[244, 164, 231],
			[126, 227, 136],
			[219, 188, 72],
		]
		_color_map = (
			LevelGenerator.compute_color_map_for_rgb_with_pattern(
				puzzle_size, regions, _rgb_v6, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_rgb(puzzle_size, regions, _rgb_v6)
		)
	elif not _ed and ABTestManager.region_color.is_palette_v7(): # AB：palette v7
		_region_colors = PackedColorArray(
			[
				Color("#b67c54"),
				Color("#ffaf92"),
				Color("#37b95e"),
				Color("#89c4e4"),
				Color("#a673d8"),
				Color("#a4da86"),
				Color("#6767c3"),
				Color("#e3bd4d"),
				Color("#fbafea"),
				Color("#45b7b3"),
				Color("#dd8240"),
				Color("#e4699c"),
			]
		)
		var _rgb_v7: Array = [
			[182, 124, 84],
			[255, 175, 146],
			[55, 185, 94],
			[137, 196, 228],
			[166, 115, 216],
			[164, 218, 134],
			[103, 103, 195],
			[227, 189, 77],
			[251, 175, 234],
			[69, 183, 179],
			[221, 130, 64],
			[228, 105, 156],
		]
		_color_map = (
			LevelGenerator.compute_color_map_for_rgb_with_pattern(
				puzzle_size, regions, _rgb_v7, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_rgb(puzzle_size, regions, _rgb_v7)
		)

	# 先收集场景里已经摆好的 Cell_r_c 节点（编辑器预览与场景复用）
	var prebaked: Dictionary = {} # 收集场景里已摆好的 Cell_r_c
	for child in get_children():
		if child is CellView and String(child.name).begins_with("Cell_"):
			var rc: PackedStringArray = String(child.name).trim_prefix("Cell_").split("_")
			# 节点名要能解析成合法的 (行,列) 且不越界
			if (
				rc.size() == 2
				and rc[0].is_valid_int()
				and rc[1].is_valid_int()
				and int(rc[0]) < puzzle_size
				and int(rc[1]) < puzzle_size
			):
				prebaked[String(child.name)] = child

	# 丢掉不在 prebaked 名单里的旧子节点（换尺寸时用）
	for child in get_children():
		if prebaked.has(String(child.name)):
			continue
		remove_child(child)
		child.queue_free()
	_cells = [] # 重建格子矩阵
	_coord_labels = [] # 坐标 Label 也清空

	# 逐行逐列铺格子
	for r in range(puzzle_size):
		var row: Array = []
		for c in range(puzzle_size):
			var key: String = "Cell_%d_%d" % [r, c] # 节点名就是坐标键
			var cell: CellView = prebaked.get(key) as CellView # 优先复用场景里已有的格子
			if cell == null:
				cell = _CELL_SCENE.instantiate() as CellView
				# 坐标换算：左上留白 + 槽位 + 单侧间隙
				cell.position = Vector2(
					BOARD_PADDING + c * SLOT_PX + CELL_GAP,
					BOARD_PADDING + r * SLOT_PX + CELL_GAP,
				)

				add_child(cell)

				cell.name = key # 新格子的名字也要符合 Cell_r_c 约定
			elif recycle_reused: # 复用旧格子时先复位到空态
				cell._reset_to_empty_baseline()

			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE # 格子不吃鼠标，输入由棋盘统一识别

			var region_idx: int = _regions[r][c] # 区域号
			# 区域号 → 调色板下标（越界时退化成取模）
			var ci: int = (
				_color_map[region_idx]
				if region_idx < _color_map.size()
				else (region_idx % _region_colors.size())
			)
			ci = ci % _region_colors.size() # 再夹一次，防止调色板为空
			cell.set_region_color(_region_colors[ci]) # 注入本格区域底色

			cell.reset_clap_tracking() # 清本格「打过叉 / 错过」追踪

			cell.set_auto_mark_locked(false) # 解锁输入
			row.append(cell)
		_cells.append(row)

	apply_compensated_cell_corner_radius() # 圆角按当前缩放补偿

	_rebuild_coord_labels() # 重建坐标数字
	_rebuild_auto_mark_btns() # 重建行列自动打叉按钮

	if not OS.has_feature("rel") and not _ed: # 非 release 构建才建保护区可视化
		_ensure_zone_viz()
	queue_redraw() # 底色圆角在 _draw 里算，需要重绘


# ---- 分帧预热（避免一次性实例化太多格子卡帧） ----
const _PREWARM_CELLS_PER_FRAME: int = 4 # 每帧最多实例化 4 个格子


# 分帧预建 size×size 个空格子；base_game_page 在正式 setup 前 await 它
func prewarm_cells(size: int) -> void:
	if size <= 0 or not _cells.is_empty(): # 尺寸非法或已有格子时不做
		return
	if get_node_or_null("Cell_0_0") != null: # 场景里已摆好 Cell_0_0，说明不需要预热
		return
	var built: int = 0
	for r in range(size):
		for c in range(size):
			if not _cells.is_empty():
				return
			var cell: CellView = _CELL_SCENE.instantiate() as CellView
			cell.position = Vector2(
				BOARD_PADDING + c * SLOT_PX + CELL_GAP,
				BOARD_PADDING + r * SLOT_PX + CELL_GAP,
			)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(cell)
			cell.name = "Cell_%d_%d" % [r, c]
			built += 1
			if built % _PREWARM_CELLS_PER_FRAME == 0: # 攒够一批就让出一帧
				await get_tree().process_frame # 等下一帧再继续


# ================= 坐标换算 =================
# 对外查询：格子边长、格子矩形、格子中心，以及本地坐标 → 格子
func get_cell_size() -> int:
	return CELL_PX


# 缩放后的可见边长（像素）；当前全仓未被调用
func get_visible_cell_size() -> float:
	return CELL_PX * scale.x


# (行,列) → 棋盘本地矩形（未含缩放）
func cell_to_local_rect(r: int, c: int) -> Rect2:
	return Rect2(
		BOARD_PADDING + c * SLOT_PX + CELL_GAP,
		BOARD_PADDING + r * SLOT_PX + CELL_GAP,
		CELL_PX,
		CELL_PX,
	)


# (行,列) → 全局中心点（引导手势 / 粒子定位用）
func get_cell_global_center(r: int, c: int) -> Vector2:
	var local_rect: Rect2 = cell_to_local_rect(r, c)
	return global_position + local_rect.get_center() * scale


# ================= 绘制 =================
# 画棋盘底色：圆角按缩放补偿，编辑器里按理论尺寸居中
func _draw() -> void:
	if _board_bg_style != null:
		var s: float = scale.x if scale.x > 0.0 else 1.0 # 缩放非法时按 1.0 处理
		_board_bg_style.set_corner_radius_all(int(round(BOARD_BG_CORNER_RADIUS / s))) # 圆角反向补偿，缩小时视觉半径不变

		var bg_size: Vector2 = size
		var bg_origin: Vector2 = Vector2.ZERO
		if Engine.is_editor_hint() and _puzzle_size > 0:
			bg_size = intrinsic_size_for(_puzzle_size) # 编辑器预览按理论尺寸居中
			bg_origin = Vector2(
				maxf(0.0, (size.x - bg_size.x) * 0.5),
				maxf(0.0, (size.y - bg_size.y) * 0.5),
			)
		draw_style_box(_board_bg_style, Rect2(bg_origin, bg_size))
	if _puzzle_size == 0: # 还没初始化就不画
		return


# ================= 状态写入（上层唯一入口） =================
# 改单格状态：越界/未初始化忽略，猫与锁定叉不可被覆盖，只有真变化才发信号
func set_cell_state(
	r: int,
	c: int,
	state: int,
	is_play_anim: bool = true,
	show_cat_visual: bool = true,
	source: int = ChangeSource.USER_ACTION,
	split_press: bool = false
) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size: # 越界忽略
		return
	if _cells.is_empty(): # 还没 setup（没有格子）忽略
		return

	var cur: int = (_cells[r][c] as CellView).get_state() # 当前状态
	if cur == CellState.CAT and state != CellState.CAT: # 猫一旦落下就不允许被改成别的状态
		return

	if cur == CellState.LOCKED_MARK: # 锁定叉是终态
		return
	if state == CellState.CAT: # 落猫：记账并震动
		_last_cat_cell = Vector2i(r, c)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3) # 三级震动
	# 参数原样转给 CellView.change_state()
	(_cells[r][c] as CellView).change_state(
		{
			"state": state,
			"play_anim": is_play_anim,
			"show_cat_visual": show_cat_visual,
			"split_press": split_press
		}
	)
	if cur != state: # 状态确实变了才广播
		cell_state_changed.emit(r, c, state, source)


# ================= 自动打叉与锁定 =================
# 转发「松手回弹」（分屏按压用）
func play_mark_release(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	(_cells[r][c] as CellView).play_mark_release()


# 自动打叉：只允许把空格变成叉，播 AutomaticAppear 出场动画
func play_auto_cross(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	if (_cells[r][c] as CellView).get_state() != CellState.EMPTY: # 只对空格生效
		return
	(_cells[r][c] as CellView).change_state(
		{"state": CellState.MARK, "play_anim": true, "appear_anim": "AutomaticAppear"}
	)
	cell_state_changed.emit(r, c, CellState.MARK, ChangeSource.AUTOMARK)


# 预置自动打叉（只改状态不播动画），成功返回 true
func preset_auto_cross(r: int, c: int) -> bool:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return false
	var cell: CellView = _cells[r][c] as CellView
	if cell.get_state() != CellState.EMPTY:
		return false
	cell.preset_mark_for_auto_cross()
	cell_state_changed.emit(r, c, CellState.MARK, ChangeSource.AUTOMARK)
	return true


# 补播预置叉的出场动画
func play_pending_auto_cross_appear(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	(_cells[r][c] as CellView).play_pending_auto_cross_appear()


# 自动撤叉：只把普通叉改回空格，播 AutomaticDisappear
func play_auto_uncross(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	var cell: CellView = _cells[r][c] as CellView
	if cell.get_state() != CellState.MARK: # 只对普通叉生效（错标 / 锁定叉不动）
		return
	cell.change_state(
		{"state": CellState.EMPTY, "play_anim": true, "disappear_anim": "AutomaticDisappear"}
	)
	cell_state_changed.emit(r, c, CellState.EMPTY, ChangeSource.AUTOMARK)


# 把叉升级成锁定叉（不可再改），可指定锁定动画
func lock_mark(
	r: int,
	c: int,
	lock_anim: String = "",
	play_anim: bool = true,
	source: int = ChangeSource.AUTOMARK
) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	var cell: CellView = _cells[r][c] as CellView
	if cell.get_state() != CellState.MARK: # 只有普通叉能被锁定
		return
	cell.change_state(
		{"state": CellState.LOCKED_MARK, "play_anim": play_anim, "lock_anim": lock_anim}
	)
	cell_state_changed.emit(r, c, CellState.LOCKED_MARK, source)


# 锁 / 解锁单格输入（自动流程中禁止玩家改）
func set_cell_input_locked(r: int, c: int, locked: bool) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	(_cells[r][c] as CellView).set_auto_mark_locked(locked)


# 查询单格输入是否被锁
func is_cell_input_locked(r: int, c: int) -> bool:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return false
	return (_cells[r][c] as CellView).is_auto_mark_locked()


# ---- 只读查询接口（上层与手势识别器调用） ----
func get_puzzle_size() -> int:
	return _puzzle_size


# 取某行 / 某列的自动打叉按钮；axis 0=行 1=列，越界返回 null
func get_axis_auto_mark_btn(axis: int, idx: int) -> Control:
	var arr: Array = _row_auto_mark_btns if axis == 0 else _col_auto_mark_btns
	if idx < 0 or idx >= arr.size():
		return null
	return arr[idx] as Control


# 取按钮的全局矩形（引导层用来画光圈）
func get_axis_auto_mark_btn_global_rect(axis: int, idx: int) -> Rect2:
	var btn: Control = get_axis_auto_mark_btn(axis, idx)
	if btn == null:
		return Rect2()
	return btn.get_global_transform() * Rect2(Vector2.ZERO, btn.size)


# 出场光环特效通过 call() 取的额外节点：每项 {node, ring}，先列按钮、后行按钮
func get_intro_extra_nodes(n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	for c in range(_col_auto_mark_btns.size()):
		var col_btn: Control = _col_auto_mark_btns[c] as Control
		if col_btn != null:
			out.append({"node": col_btn, "ring": (n - 1) + c + 1})
	for r in range(_row_auto_mark_btns.size()):
		var row_btn: Control = _row_auto_mark_btns[r] as Control
		if row_btn != null:
			out.append({"node": row_btn, "ring": (n - 1) + (n - 1 - r) + 1})
	return out


# 读单格状态；越界或未初始化返回 EMPTY
func get_cell_state(r: int, c: int) -> int:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return CellState.EMPTY
	return (_cells[r][c] as CellView).get_state()


# 把格子标成错标（不播动画）；已经是错标则不重复发信号
func mark_cell_error(r: int, c: int, source: int = ChangeSource.USER_ACTION) -> void:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	var cur: int = (_cells[r][c] as CellView).get_state()

	if cur == CellState.LOCKED_MARK:
		return
	(_cells[r][c] as CellView).change_state({"state": CellState.ERROR, "play_anim": false})
	if cur != CellState.ERROR:
		cell_state_changed.emit(r, c, CellState.ERROR, source)


# 错标反馈（会播动画）
func play_error_feedback(r: int, c: int, source: int = ChangeSource.USER_ACTION) -> void:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	var cur: int = (_cells[r][c] as CellView).get_state()
	if cur == CellState.LOCKED_MARK:
		return
	(_cells[r][c] as CellView).change_state({"state": CellState.ERROR})
	if cur != CellState.ERROR:
		cell_state_changed.emit(r, c, CellState.ERROR, source)


# ================= 整盘猫动画 =================
# 通关回放：全盘猫重播出现动画，最后落下的那只带粒子
func replay_all_cat_appear() -> void:
	if _cells.is_empty():
		return
	SoundManager.play(SoundManager.Kind.ALL_CLEARED) # 通关音效
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.force_play_appear(Vector2i(r, c) == _last_cat_cell) # 只有最后落下的猫开粒子


# 全盘猫进入「哭」循环（猜错时）
func play_cat_cry_loop_all() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_cry_loop()


# 全盘猫播一次沮丧表情
func play_cat_frustrated_all() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_frustrated_once()


# 指定格子播一次沮丧表情（只对猫生效）
func play_cat_frustrated_at(cells: Array) -> void:
	if _cells.is_empty():
		return
	for p: Vector2i in cells:
		var cell := get_cell_view(p.x, p.y)
		if cell != null and cell.get_state() == CellState.CAT:
			cell.play_frustrated_once()


# 全盘猫恢复 idle
func revive_all_cat_to_idle() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.revive_to_idle()


# ================= 棋盘导出 =================
# 导出完整状态棋盘（草稿 / 错标 / 锁定叉都是原值），交给规则引擎判定
func get_board() -> Array:
	var board: Array = []
	for r in range(_puzzle_size):
		var row: Array[int] = []
		row.resize(_puzzle_size)
		for c in range(_puzzle_size):
			row[c] = (_cells[r][c] as CellView).get_state()
		board.append(row)
	return board


# 导出「折叠」棋盘：草稿算空、错标与锁定叉算叉，供提示引擎解题
func get_cell_state_folded_board() -> Array:
	var board: Array = []
	for r in range(_puzzle_size):
		var row: Array[int] = []
		row.resize(_puzzle_size)
		for c in range(_puzzle_size):
			var s: int = (_cells[r][c] as CellView).get_state()
			if CellState.is_draft(s): # 草稿一律当空格
				row[c] = CellState.EMPTY
			elif s == CellState.ERROR or s == CellState.LOCKED_MARK: # 错标 / 锁定叉一律当普通叉
				row[c] = CellState.MARK
			else:
				row[c] = s
		board.append(row)
	return board


# ================= 统计与查询 =================
# 单格是否错标
func is_cell_error(r: int, c: int) -> bool:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return false
	return (_cells[r][c] as CellView).get_state() == CellState.ERROR


# 错标格数量
func count_error_cells() -> int:
	return _count_cells_in_state(CellState.ERROR)


# 叉数量（普通叉 + 锁定叉）
func count_mark_cells() -> int:
	return _count_cells_in_state(CellState.MARK) + _count_cells_in_state(CellState.LOCKED_MARK)


# 空格数量（空 + 草稿，与 CellState.is_blank 一致）
func count_empty_cells() -> int:
	if _cells.is_empty():
		return 0
	var n: int = 0
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if CellState.is_blank((_cells[r][c] as CellView).get_state()):
				n += 1
	return n


# 猫数量
func count_cat_cells() -> int:
	return _count_cells_in_state(CellState.CAT)


# 按状态统计格子数（未初始化返回 0）
func _count_cells_in_state(state: int) -> int:
	if _cells.is_empty():
		return 0
	var n: int = 0
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if (_cells[r][c] as CellView).get_state() == state:
				n += 1
	return n


# 取单格区域底色（区域表为空或越界返回白色）
func get_cell_region_color(r: int, c: int) -> Color:
	if _regions.is_empty() or r < 0 or c < 0 or r >= _puzzle_size or c >= _puzzle_size:
		return Color.WHITE
	var region_idx: int = _regions[r][c]
	var ci: int = (
		_color_map[region_idx]
		if region_idx < _color_map.size()
		else (region_idx % _region_colors.size())
	)
	ci = ci % _region_colors.size()
	return _region_colors[ci]


# 取单格 CellView 节点；越界或未初始化返回 null
func get_cell_view(r: int, c: int) -> CellView:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return null
	return _cells[r][c] as CellView


# 本地坐标 → 格子；返回 (列, 行)——注意 x 是列、y 是行，与 _cells[行][列] 相反
# 落在棋盘外返回 (-1,-1)
func pointer_to_cell(px: float, py: float) -> Vector2i:
	if _puzzle_size == 0:
		return Vector2i(-1, -1)
	var col: int = int((px - BOARD_PADDING) / SLOT_PX)
	var row: int = int((py - BOARD_PADDING) / SLOT_PX)
	if row < 0 or row >= _puzzle_size or col < 0 or col >= _puzzle_size:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


# 更新保护区可视化数据（SwipeGuardRecognizer 每次手势都推过来）
func update_swipe_protection_zone(lock: Dictionary) -> void:
	if _zone_viz != null and is_instance_valid(_zone_viz):
		_zone_viz.set_zone(lock)


# 切换保护区可视化显隐，返回切换后的状态（cheat 命令用）
func toggle_swipe_zone_viz() -> bool:
	_swipe_viz_on = not _swipe_viz_on
	if _zone_viz != null and is_instance_valid(_zone_viz):
		_zone_viz.set_enabled(_swipe_viz_on)
	return _swipe_viz_on


# 确保可视化节点存在并同步尺寸 / 开关（仅非 release 构建调用）
func _ensure_zone_viz() -> void:
	if _zone_viz == null or not is_instance_valid(_zone_viz) or not _zone_viz.is_inside_tree():
		_zone_viz = SwipeZoneDebugOverlay.new()
		_zone_viz.name = "SwipeZoneViz"
		add_child(_zone_viz)
	_zone_viz.configure(SLOT_PX, BOARD_PADDING, _puzzle_size)
	_zone_viz.set_enabled(_swipe_viz_on)


# ================= 提示高亮 =================
# 设置提示高亮：与上一批求差集，新增的闪起来、移除的收起来
func set_hint_cells(unit_cells: Array[Vector2i], key_cell: Vector2i) -> void:
	for old in _hint_unit_cells:
		if not unit_cells.has(old):
			(_cells[old.x][old.y] as CellView).play_hide_hint()
	for new_cell in unit_cells:
		if not _hint_unit_cells.has(new_cell):
			(_cells[new_cell.x][new_cell.y] as CellView).play_hint()
	_hint_unit_cells = unit_cells
	_hint_key_cell = key_cell
	queue_redraw()


# 清掉全部提示高亮
func clear_hint_cells() -> void:
	for cell in _hint_unit_cells:
		(_cells[cell.x][cell.y] as CellView).play_hide_hint()
	_hint_unit_cells = []
	_hint_key_cell = Vector2i(-1, -1)
	queue_redraw()


# ================= 区域色查询 =================
# 区域号 → 调色板下标（越界时取模）
func get_region_color_index(region_idx: int) -> int:
	if region_idx < _color_map.size():
		return _color_map[region_idx] % _region_colors.size()
	return region_idx % _region_colors.size()


# 区域号 → 颜色（下标越界返回白色）
func get_region_color(region_idx: int) -> Color:
	var ci: int = get_region_color_index(region_idx)
	if ci < _region_colors.size():
		return _region_colors[ci]
	return Color.WHITE


# 该格所属区域共有几格
func get_region_cell_count(r: int, c: int) -> int:
	if _regions.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return 0
	var rid: int = int(_regions[r][c])
	var n: int = 0
	for rr in range(_puzzle_size):
		for cc in range(_puzzle_size):
			if int(_regions[rr][cc]) == rid:
				n += 1
	return n


# 该格所属区域里是否出现过叉（R4+ 鼓掌提示的前置条件）
func is_region_ever_marked_x(r: int, c: int) -> bool:
	if (
		_regions.is_empty()
		or _cells.is_empty()
		or r < 0
		or r >= _puzzle_size
		or c < 0
		or c >= _puzzle_size
	):
		return false
	var rid: int = int(_regions[r][c])
	for rr in range(_puzzle_size):
		for cc in range(_puzzle_size):
			if int(_regions[rr][cc]) != rid:
				continue
			if (_cells[rr][cc] as CellView).has_ever_marked_x():
				return true
	return false


# 该格所属区域里是否出现过错标
func is_region_ever_errored(r: int, c: int) -> bool:
	if (
		_regions.is_empty()
		or _cells.is_empty()
		or r < 0
		or r >= _puzzle_size
		or c < 0
		or c >= _puzzle_size
	):
		return false
	var rid: int = int(_regions[r][c])
	for rr in range(_puzzle_size):
		for cc in range(_puzzle_size):
			if int(_regions[rr][cc]) != rid:
				continue
			if (_cells[rr][cc] as CellView).has_ever_errored():
				return true
	return false


# ================= 提示预演 =================
# 指定格播 R2 预览动画
func play_r2_preview_cell(r: int, c: int) -> void:
	if r >= 0 and r < _cells.size() and c >= 0 and c < (_cells[r] as Array).size():
		(_cells[r][c] as CellView).play_r2_preview()


# 同上，可延迟若干秒（多格排队预览）
func play_r2_preview_cell_delayed(r: int, c: int, delay: float) -> void:
	if r >= 0 and r < _cells.size() and c >= 0 and c < (_cells[r] as Array).size():
		(_cells[r][c] as CellView).play_r2_preview(delay)


# ================= 坐标数字 =================
# 切换行列坐标数字；状态写回 GameState 以便跨局保留
func toggle_coords() -> void:
	_coord_visible = not _coord_visible
	GameState.coords_visible = _coord_visible
	for lbl in _coord_labels:
		lbl.visible = _coord_visible


# 重建坐标数字：列号在棋盘上方、行号在左侧，都从 1 开始
func _rebuild_coord_labels() -> void:
	for lbl in _coord_labels:
		lbl.queue_free()
	_coord_labels = []
	if _puzzle_size == 0:
		return
	var ox: int = BOARD_PADDING
	var oy: int = BOARD_PADDING

	for c in range(_puzzle_size):
		var lbl := Label.new()
		lbl.text = str(c + 1) # 列号从 1 开始
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.85))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(SLOT_PX, 44)
		lbl.position = Vector2(ox + c * SLOT_PX, oy - 46)
		lbl.visible = _coord_visible
		add_child(lbl)
		_coord_labels.append(lbl)

	for r in range(_puzzle_size):
		var lbl := Label.new()
		lbl.text = str(r + 1) # 行号从 1 开始
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.85))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(44, SLOT_PX)
		lbl.position = Vector2(ox - 48, oy + r * SLOT_PX)
		lbl.visible = _coord_visible
		add_child(lbl)
		_coord_labels.append(lbl)


# ================= 自动打叉按钮 =================
# 重建行列按钮：编辑器预览不受 AB 限制，运行时需 AB 开关命中当前关卡
func _rebuild_auto_mark_btns() -> void:
	for btn in _row_auto_mark_btns:
		if is_instance_valid(btn):
			btn.queue_free()
	for btn in _col_auto_mark_btns:
		if is_instance_valid(btn):
			btn.queue_free()
	_row_auto_mark_btns = []
	_col_auto_mark_btns = []
	if _puzzle_size == 0:
		return

	var _ed: bool = Engine.is_editor_hint()
	if _ed:
		if not preview_auto_mark_btns:
			return
	else:
		if ABTestManager == null or ABTestManager.game_auto_mark == null or GameState == null: # ABTest 或 GameState 未就绪就放弃
			return
		if not ABTestManager.game_auto_mark.is_dot_toggle_enabled_at(GameState.get_current_level()): # 该关卡没开「点号自动打叉」
			return

	var btn_pivot: Vector2 = Vector2(_AUTO_MARK_BTN_W * 0.5, _AUTO_MARK_BTN_H * 0.5)

	for c in range(_puzzle_size):
		var btn: Node = _AUTO_MARK_BTN_SCENE.instantiate()
		var btn_ctl: Control = btn as Control
		btn_ctl.pivot_offset = btn_pivot
		add_child(btn)
		_apply_editor_btn_default_visual(btn, _ed)
		_col_auto_mark_btns.append(btn)

		if not _ed:
			var col_idx: int = c
			# 按下时把 (轴, 序号, 按下前是否已标记) 抛给上层
			btn.pressed_with_state.connect(
				func(is_marked_before: bool) -> void:
					axis_auto_mark_pressed.emit(1, col_idx, is_marked_before)
			)

	for r in range(_puzzle_size):
		var btn: Node = _AUTO_MARK_BTN_SCENE.instantiate()
		var btn_ctl: Control = btn as Control
		btn_ctl.rotation_degrees = 90.0
		btn_ctl.pivot_offset = btn_pivot
		add_child(btn)
		_apply_editor_btn_default_visual(btn, _ed)
		_row_auto_mark_btns.append(btn)
		if not _ed:
			var row_idx: int = r
			btn.pressed_with_state.connect(
				func(is_marked_before: bool) -> void:
					axis_auto_mark_pressed.emit(0, row_idx, is_marked_before)
			)

	apply_inverse_scale_to_auto_mark_btns() # 按钮反向缩放，保持视觉大小


# 按当前缩放补偿所有格子的圆角
func apply_compensated_cell_corner_radius() -> void:
	if scale.x <= 0.0:
		return
	if _cells.is_empty():
		return
	for row in _cells:
		for cell in row:
			if cell is CellView:
				(cell as CellView).set_corner_radius_compensated(scale.x)


# 把自动打叉按钮按 1/scale 反向缩放，并摆到棋盘外缘
func apply_inverse_scale_to_auto_mark_btns() -> void:
	if scale.x <= 0.0:
		return
	if _puzzle_size == 0:
		return
	var inv: float = 1.0 / scale.x # 反向缩放系数
	var inv_scale: Vector2 = Vector2(inv, inv)

	var preview_offset_x: float = 0.0 # 编辑器预览时的居中偏移
	var preview_offset_y: float = 0.0
	if Engine.is_editor_hint():
		var intrinsic: Vector2 = intrinsic_size_for(_puzzle_size)
		preview_offset_x = maxf(0.0, (size.x - intrinsic.x) * 0.5)
		preview_offset_y = maxf(0.0, (size.y - intrinsic.y) * 0.5)
	var ox: int = BOARD_PADDING
	var oy: int = BOARD_PADDING

	var col_y_dist_local: float = (_AUTO_MARK_BTN_OUT_GAP + _AUTO_MARK_BTN_H * 0.5) * inv # 列按钮中心到棋盘上沿的距离（本地坐标）
	var row_x_dist_local: float = (_AUTO_MARK_BTN_OUT_GAP + _AUTO_MARK_BTN_H * 0.5 + 2.0) * inv # 行按钮中心到棋盘右沿的距离（+2 像素让开圆角）

	for c in range(_col_auto_mark_btns.size()):
		var btn: Control = _col_auto_mark_btns[c] as Control
		if not is_instance_valid(btn):
			continue
		btn.scale = inv_scale
		var center_x: float = ox + c * SLOT_PX + SLOT_PX * 0.5
		var center_y: float = oy - col_y_dist_local
		btn.position = Vector2(
			center_x - _AUTO_MARK_BTN_W * 0.5 + preview_offset_x,
			center_y - _AUTO_MARK_BTN_H * 0.5 + preview_offset_y,
		)

	for r in range(_row_auto_mark_btns.size()):
		var btn: Control = _row_auto_mark_btns[r] as Control
		if not is_instance_valid(btn):
			continue
		btn.scale = inv_scale
		var center_x: float = ox + _puzzle_size * SLOT_PX + row_x_dist_local
		var center_y: float = oy + r * SLOT_PX + SLOT_PX * 0.5
		btn.position = Vector2(
			center_x - _AUTO_MARK_BTN_W * 0.5 + preview_offset_x,
			center_y - _AUTO_MARK_BTN_H * 0.5 + preview_offset_y,
		)


# 编辑器预览时把按钮切成「未标记」的默认外观
func _apply_editor_btn_default_visual(btn: Node, is_editor: bool) -> void:
	if not is_editor:
		return
	var sprite_mark: Node = btn.get_node_or_null("BtnAutoMark")
	var sprite_unmark: Node = btn.get_node_or_null("BtnAutoUnMark")
	if sprite_mark != null:
		sprite_mark.visible = true
	if sprite_unmark != null:
		sprite_unmark.visible = false


# 刷新某个行列按钮的标记态（上层按盘面算完再回写）
func refresh_axis_auto_mark_state(axis: int, idx: int, is_marked: bool) -> void:
	var arr: Array = _row_auto_mark_btns if axis == 0 else _col_auto_mark_btns
	if idx < 0 or idx >= arr.size():
		return
	var btn = arr[idx]
	if not is_instance_valid(btn):
		return
	btn.set_marked(is_marked)


# 查询某个行列按钮当前是否已标记
func is_axis_auto_mark_marked(axis: int, idx: int) -> bool:
	var arr: Array = _row_auto_mark_btns if axis == 0 else _col_auto_mark_btns
	if idx < 0 or idx >= arr.size():
		return false
	var btn = arr[idx]
	if not is_instance_valid(btn):
		return false
	return btn.is_marked()


# ================= 输入 =================
# 棋盘只把鼠标事件翻译成拖拽信号，格子状态由上层决定
func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if pointer_to_cell(mb.position.x, mb.position.y).x >= 0: # .x >= 0 表示点在棋盘内
					_dragging = true
					cell_drag_start.emit(mb.position)
				else:
					_dragging = false
			else:
				_dragging = false
				cell_drag_end.emit() # 抬手：结束本笔


# 全局鼠标移动：拖拽中才算「经过」，坐标要转成棋盘本地坐标
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT: # 必须按住左键
			if not _dragging:
				return
			var local_pos: Vector2 = (make_input_local(mm) as InputEventMouseMotion).position # 转成本地坐标后再上报
			cell_drag_over.emit(local_pos)


# ================= 编辑器预览 =================
# 用题库第一关（9x9 rank1）铺静态预览，方便在编辑器里调外观
func _render_editor_preview() -> void:
	var levels: Array = BankData.get_levels(9, 1) # 只取 9x9 题库第 1 关
	if levels.is_empty():
		push_warning("BoardView: editor_preview 未取到 9x9 题库(bankData9x9.json rank 1)")
		return
	var entry: Dictionary = levels[0]
	var raw_regions: Array = entry.get("regionMap", [])
	if raw_regions.is_empty():
		push_warning("BoardView: editor_preview 题目缺 regionMap")
		return

	var int_regions: Array = [] # regionMap 里的值统一转 int
	for row_arr: Array in raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)
	var sz: int = int_regions.size() # 预览边长由数据决定
	var color_map: Array[int] = LevelGenerator.compute_color_map_with_seed(sz, int_regions, 0)
	setup(sz, int_regions, color_map)

	if not resized.is_connected(_relayout_editor_preview_cells): # 尺寸变化时重新居中（只连一次）
		resized.connect(_relayout_editor_preview_cells)
	_relayout_editor_preview_cells()


# 尺寸变化时把格子重新居中
func _relayout_editor_preview_cells() -> void:
	if _puzzle_size == 0 or _cells.is_empty():
		return
	var intrinsic: Vector2 = intrinsic_size_for(_puzzle_size)
	var offset_x: float = maxf(0.0, (size.x - intrinsic.x) * 0.5) # 与 _draw 用同一套居中算法
	var offset_y: float = maxf(0.0, (size.y - intrinsic.y) * 0.5)
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell: CellView = _cells[r][c]
			if cell == null:
				continue
			cell.position = Vector2(
				BOARD_PADDING + c * SLOT_PX + CELL_GAP + offset_x,
				BOARD_PADDING + r * SLOT_PX + CELL_GAP + offset_y,
			)

	if preview_auto_mark_btns: # 勾了按钮预览就重建
		_rebuild_auto_mark_btns()
	queue_redraw()


# 关掉预览：断信号、清所有子节点、复位尺寸
func _clear_editor_preview() -> void:
	if resized.is_connected(_relayout_editor_preview_cells):
		resized.disconnect(_relayout_editor_preview_cells)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cells = []
	_coord_labels = []
	_puzzle_size = 0
	queue_redraw()
