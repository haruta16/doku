## 棋盘视图总管：建立区域格子、集中复用猫骨骼，承接输入坐标与状态通知，并协调提示和全盘反馈。
@tool
class_name BoardView
extends Control

# ---- 布局常量（像素） ----
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn") # 单个格子场景（cell.tscn，内含 CellView）
const BOARD_PADDING: int = 15 # 棋盘四周留白（像素）
const CELL_PX: int = 100 # 格子边长（像素，不含间隙）
const CELL_GAP: int = 4 # 格子间隙（像素）
const SLOT_PX: int = CELL_PX + 2 * CELL_GAP # 单格槽位 = 边长 + 两侧间隙（像素）

const BOARD_BG_CORNER_RADIUS: int = 30 # 棋盘底色圆角半径（设计值，绘制时按缩放补偿）

const WARM_POOL_RGB: Array = [
	[248, 155, 229],
	[205, 164, 0],
	[168, 109, 74],
	[251, 217, 131],
	[250, 157, 92],
	[211, 111, 143],
]
const COOL_POOL_RGB: Array = [
	[137, 121, 218],
	[139, 213, 125],
	[56, 169, 192],
	[42, 140, 83],
	[80, 118, 165],
	[165, 198, 231],
]

const PALETTE_V13_RGB: Array = [
	[174, 217, 148],
	[250, 180, 208],
	[228, 187, 73],
	[167, 191, 215],
	[107, 188, 231],
	[213, 115, 116],
	[173, 111, 72],
	[91, 117, 178],
	[151, 120, 214],
	[72, 181, 178],
	[255, 170, 109],
	[235, 133, 183],
]
const PALETTE_V14_RGB: Array = [
	[249, 217, 106],
	[250, 175, 92],
	[212, 115, 99],
	[238, 146, 167],
	[249, 176, 247],
	[128, 219, 140],
	[199, 201, 74],
	[70, 180, 169],
	[129, 216, 233],
	[119, 175, 222],
	[165, 144, 221],
	[104, 98, 168],
]


## 把 0～255 的 RGB 三元组转换为 Godot 调色板。
static func _colors_from_rgb(rgb: Array) -> PackedColorArray:
	var out := PackedColorArray()
	for c in rgb:
		out.append(Color8(c[0], c[1], c[2]))
	return out


enum ChangeSource {
	USER_ACTION,
	RESTORE,
	LOCATE,
	HINT,
	UNDO,
	PREFILL,
	AUTO_COMPLETE,
	DRAFT_APPLY,
	INTEGRITY_HEAL,
	MOUSE,
	DRAFT_ROLLBACK,
	FULL_MARK_AUTO_CROSS
}


## 只为用户操作、提示、鼠标效果和草稿提交启用消除实验动画。
static func _should_apply_eliminate_effect(source: int) -> bool:
	return (
		source
		in [
			ChangeSource.USER_ACTION,
			ChangeSource.HINT,
			ChangeSource.MOUSE,
			ChangeSource.DRAFT_APPLY,
		]
	)


## 读取棋盘布局实验的边距与槽位；编辑器或配置缺失时使用设计常量。
static func _grid_padding_slot(sz: int) -> Vector2i:
	var padding: int = BOARD_PADDING
	var slot: int = SLOT_PX
	if not Engine.is_editor_hint() and ABTestManager != null and ABTestManager.game_grid_ui != null:
		var lo: Dictionary = ABTestManager.game_grid_ui.solve_local_layout(sz)
		padding = lo.padding
		slot = lo.slot
	return Vector2i(padding, slot)


## 按格数、槽位和两侧留白计算棋盘未缩放的固有尺寸。
static func intrinsic_size_for(sz: int) -> Vector2:
	var ps: Vector2i = _grid_padding_slot(sz)
	var n: int = ps.y * sz + ps.x * 2
	return Vector2(n, n)


# ---- 棋盘数据（由 setup 注入） ----
var _puzzle_size: int = 0 # 棋盘边长；0 表示还没初始化
var _regions: Array = [] # 区域表 regions[行][列] = 区域号
var _color_map: Array[int] = [] # 区域号 → 调色板下标
var _region_colors: PackedColorArray = PackedColorArray() # 本次使用的区域调色板

var _palette_override: PackedColorArray = PackedColorArray()
var _cells: Array = [] # 格子节点二维数组 _cells[行][列]（视图层真源）

const PATTERN_ICONS: Array[Texture2D] = [
	preload("res://assets/sprites/game/pattern_icon/pattern_claw.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_bell.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_fishbone.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_whisker.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_sparkle.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_ear.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_heart.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_yarn.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_sprout.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_paw.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_triangle.png"),
	preload("res://assets/sprites/game/pattern_icon/pattern_dot.png"),
]
var _pattern_on: bool = false
var _pattern_keep_on_filled: bool = false

var _pattern_colors_by_slot: PackedColorArray = PackedColorArray()


## 按当前区域底色与色盲模式配置，预计算每个调色板槽位的图案色。
func _resolve_pattern_colors_by_slot() -> void:
	_pattern_colors_by_slot.resize(_region_colors.size())
	var cfg: BlindModColorConfig = null
	if not Engine.is_editor_hint() and ABTestManager != null:
		cfg = ABTestManager.blind_mod_color
	for i in _region_colors.size():
		if cfg != null:
			_pattern_colors_by_slot[i] = cfg.pattern_color_for(_region_colors[i])
		else:
			_pattern_colors_by_slot[i] = ColorblindPatternVariants.color_for(
				_region_colors[i], ColorblindPatternVariants.Variant.CONTROL
			)


var _region_dim_enabled: bool = false

var _region_cells: Dictionary = {}

# ---- 提示与最近落猫（视觉状态） ----
var _hint_unit_cells: Array[Vector2i] = [] # 当前高亮的提示格
var _hint_key_cell: Vector2i = Vector2i(-1, -1) # 提示关键格（仅记录，本文件内未再读）
var _last_cat_cell: Vector2i = Vector2i(-1, -1) # 最近一次落猫的格子，通关回放时给它开粒子
var _coord_visible: bool = false # 行列坐标数字是否显示
var _coord_labels: Array[Label] = [] # 坐标 Label 列表（列在前、行在后）

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

var _grid_padding: int = BOARD_PADDING
var _grid_gap: int = CELL_GAP
var _grid_slot: int = SLOT_PX
var _grid_bg_corner: int = BOARD_BG_CORNER_RADIUS

var _grid_cell_face_px: int = CELL_PX

# ---- 运行时状态 ----
var _board_bg_style: StyleBoxFlat = null # 棋盘底色样式（_draw 里画圆角矩形）

var _dragging: bool = false # 是否处于拖拽中（用来筛选移动事件）

var _touch_enabled: bool = true

var _touch_token: int = 0

var _touch_manual_locked: bool = false

var _touch_timed_lock_count: int = 0

var _touch_yielding_lock_count: int = 0

var _swipe_viz_on: bool = false # 保护区可视化是否打开（cheat 命令切换）
var _zone_viz: SwipeZoneDebugOverlay = null # 保护区可视化节点（仅非 release 构建创建）
var _last_logged_lock: Dictionary = {}

var _extra_zone_viz_on: bool = false
var _extra_zone_viz: SwipeExtraZoneDebugOverlay = null

var _touch_point_viz_on: bool = false

var _touch_point_viz: TouchPointDebugOverlay = null
var _solution_cols: Array = []

var _grid_overlay: BoardGridOverlay = null

var _region_highlight: RegionHighlightOverlay = null

# ---- 对外信号 ----
signal cell_drag_start(pos: Vector2) # 拖拽开始（本地坐标）
signal cell_drag_over(pos: Vector2) # 拖拽经过（本地坐标）
signal cell_drag_end(pos: Vector2)

signal cell_state_changed(row: int, col: int, state: int, source: int) # 格子状态真实变化才发（cur != state），上层据此记账 / 联动

signal background_rect_changed


## 建立背景样式；编辑器按开关生成预览，运行时读取布局实验和坐标显示偏好。
func _ready() -> void:
	_board_bg_style = StyleBoxFlat.new()
	_board_bg_style.bg_color = Color(1, 1, 1, 1)

	if Engine.is_editor_hint():
		if editor_preview:
			_render_editor_preview()
		return
	_load_grid_ab(_puzzle_size)
	_coord_visible = GameState.coords_visible


## 从布局实验配置更新边距、间隙、槽位、底面尺寸和外框圆角。
func _load_grid_ab(sz: int) -> void:
	if Engine.is_editor_hint() or ABTestManager == null or ABTestManager.game_grid_ui == null:
		_grid_padding = BOARD_PADDING
		_grid_gap = CELL_GAP
		_grid_slot = SLOT_PX
		_grid_bg_corner = BOARD_BG_CORNER_RADIUS
		_grid_cell_face_px = CELL_PX
		return
	var lo: Dictionary = ABTestManager.game_grid_ui.solve_local_layout(sz)
	_grid_padding = lo.padding
	_grid_gap = lo.gap
	_grid_slot = lo.slot
	var bg: Dictionary = ABTestManager.game_grid_ui.get_board_layout()
	_grid_bg_corner = bg.bg_corner
	_grid_cell_face_px = ABTestManager.game_grid_ui.get_cell_face_px()


## 从格子场景取得默认调色板，再按区域配色实验选择基础色组。
static func resolve_region_palette() -> PackedColorArray:
	var temp_cell: CellView = _CELL_SCENE.instantiate() as CellView
	var pal: PackedColorArray = temp_cell.region_colors
	temp_cell.free()

	if Engine.is_editor_hint():
		return pal

	if ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		return pal

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


## 准备猫的集中绘制层并建立棋盘；复用旧格子时可先归还猫骨骼实例。
func setup(
	puzzle_size: int,
	regions: Array,
	color_map: Array[int],
	pattern_regions: Array = [],
	recycle_reused: bool = false
) -> void:
	if recycle_reused:
		release_cats_to_pool()
	ensure_cat_batch_layer()
	_apply_setup(puzzle_size, regions, color_map, pattern_regions, recycle_reused)


## 记录外部调色板，下一次 setup 时覆盖实验配色。
func set_palette_override(colors: PackedColorArray) -> void:
	_palette_override = colors


## 取消外部配色覆盖，下一次 setup 恢复配置选择。
func clear_palette_override() -> void:
	_palette_override = PackedColorArray()


## 重置本局视图状态，计算配色并复用或创建格子，最后重建坐标、调试层与网格。
## 把区域图保存为行列数组；格子状态由 _cells 中的 CellView 持有。
func _apply_setup(
	puzzle_size: int,
	regions: Array,
	color_map: Array[int],
	pattern_regions: Array = [],
	recycle_reused: bool = false
) -> void:
	_load_grid_ab(puzzle_size)
	_puzzle_size = puzzle_size
	_regions = regions
	_color_map = color_map

	_dragging = false

	set_touch_enabled(true)

	_hint_unit_cells = []
	_hint_key_cell = Vector2i(-1, -1)
	_last_cat_cell = Vector2i(-1, -1)
	_solution_cols = []

	_region_colors = resolve_region_palette()

	var _ed: bool = Engine.is_editor_hint()
	if not _ed and ABTestManager.region_color.is_palette_v5():
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
		_color_map = (
			LevelGenerator.compute_color_map_for_rgb_with_pattern(
				puzzle_size, regions, _rgb_v5, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_rgb(puzzle_size, regions, _rgb_v5)
		)
	elif not _ed and ABTestManager.region_color.is_palette_v6():
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
	elif not _ed and ABTestManager.region_color.is_palette_v8():
		_region_colors = PackedColorArray(
			[
				Color("#d3d551"),
				Color("#d86c90"),
				Color("#767ae4"),
				Color("#e57ee0"),
				Color("#e76f58"),
				Color("#dccf95"),
				Color("#7284b3"),
				Color("#c0d1dc"),
				Color("#399295"),
				Color("#459a5e"),
				Color("#99dbb1"),
				Color("#a67b63"),
			]
		)
		var _rgb_v8: Array = [
			[211, 213, 81],
			[216, 108, 144],
			[118, 122, 228],
			[229, 126, 224],
			[231, 111, 88],
			[220, 207, 149],
			[114, 132, 179],
			[192, 209, 220],
			[57, 146, 149],
			[69, 154, 94],
			[153, 219, 177],
			[166, 123, 99],
		]
		_color_map = (
			LevelGenerator.compute_color_map_for_lab_with_pattern(
				puzzle_size, regions, _rgb_v8, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_lab(puzzle_size, regions, _rgb_v8)
		)
	elif not _ed and ABTestManager.region_color.is_all_warm():
		var _rgb_warm10: Array = WARM_POOL_RGB + COOL_POOL_RGB.slice(0, max(0, puzzle_size - 6))
		_region_colors = _colors_from_rgb(_rgb_warm10)
		_color_map = (
			LevelGenerator.compute_color_map_for_lab_with_pattern(
				puzzle_size, regions, _rgb_warm10, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_lab(puzzle_size, regions, _rgb_warm10)
		)
	elif not _ed and ABTestManager.region_color.is_all_cool():
		var _rgb_cool11: Array = COOL_POOL_RGB + WARM_POOL_RGB.slice(0, max(0, puzzle_size - 6))
		_region_colors = _colors_from_rgb(_rgb_cool11)
		_color_map = (
			LevelGenerator.compute_color_map_for_lab_with_pattern(
				puzzle_size, regions, _rgb_cool11, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_lab(puzzle_size, regions, _rgb_cool11)
		)
	elif not _ed and ABTestManager.region_color.is_palette_v13():
		_region_colors = _colors_from_rgb(PALETTE_V13_RGB)
		_color_map = (
			LevelGenerator.compute_color_map_for_lab_with_pattern(
				puzzle_size, regions, PALETTE_V13_RGB, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_lab(puzzle_size, regions, PALETTE_V13_RGB)
		)
	elif not _ed and ABTestManager.region_color.is_palette_v14():
		_region_colors = _colors_from_rgb(PALETTE_V14_RGB)
		_color_map = (
			LevelGenerator.compute_color_map_for_lab_with_pattern(
				puzzle_size, regions, PALETTE_V14_RGB, pattern_regions
			)
			if pattern_regions.size() > 0
			else LevelGenerator.compute_color_map_for_lab(puzzle_size, regions, PALETTE_V14_RGB)
		)

	if not _palette_override.is_empty():
		_region_colors = _palette_override
		_color_map = color_map

	_resolve_pattern_colors_by_slot()

	var prebaked: Dictionary = {}
	for child in get_children():
		if child is CellView and String(child.name).begins_with("Cell_"):
			var rc: PackedStringArray = String(child.name).trim_prefix("Cell_").split("_")
			if (
				rc.size() == 2
				and rc[0].is_valid_int()
				and rc[1].is_valid_int()
				and int(rc[0]) < puzzle_size
				and int(rc[1]) < puzzle_size
			):
				prebaked[String(child.name)] = child

	for child in get_children():
		if prebaked.has(String(child.name)):
			continue
		if String(child.name) == String(CellView.BATCH_LAYER_NAME):
			continue
		remove_child(child)
		child.queue_free()
	_cells = []
	_coord_labels = []

	var _single_line: bool = (
		not _ed
		and ABTestManager != null
		and ABTestManager.game_grid_ui != null
		and ABTestManager.game_grid_ui.is_single_line()
	)

	for r in range(puzzle_size):
		var row: Array = []
		for c in range(puzzle_size):
			var key: String = "Cell_%d_%d" % [r, c]
			var cell: CellView = prebaked.get(key) as CellView

			var _expect_pos := Vector2(
				_grid_padding + c * _grid_slot + _grid_gap,
				_grid_padding + r * _grid_slot + _grid_gap
			)
			if cell == null:
				cell = _CELL_SCENE.instantiate() as CellView

				add_child(cell)

				cell.name = key
			elif recycle_reused:
				cell._reset_to_empty_baseline()

			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

			cell.position = _expect_pos

			var region_idx: int = _regions[r][c]
			var ci: int = (
				_color_map[region_idx]
				if region_idx < _color_map.size()
				else (region_idx % _region_colors.size())
			)
			ci = ci % _region_colors.size()
			var region_color: Color = _region_colors[ci]
			cell.set_region_color(region_color)

			var slot: int = ci % PATTERN_ICONS.size()
			cell.configure_pattern(PATTERN_ICONS[slot], _pattern_colors_by_slot[ci])
			cell.set_pattern_mode(_pattern_on, _pattern_keep_on_filled)

			cell.reset_clap_tracking()

			cell.set_use_hard_bg(_single_line)
			cell.set_round_corners(corner_round_mask_for(r, c))

			cell.apply_cross_art_variant(false)

			cell.apply_cell_face_px(float(_grid_cell_face_px))

			cell.set_cat_costume(_cat_costume_id)
			row.append(cell)
		_cells.append(row)

	if not _cells.is_empty() and not _cells[0].is_empty():
		_cells[0][0].apply_shared_cross_stroke_track_override()

	_reset_all_cell_dim()

	_reset_all_cell_grid_blast()
	_region_cells.clear()
	if _region_dim_enabled:
		_rebuild_region_cell_index()

	apply_compensated_cell_corner_radius()

	_rebuild_coord_labels()

	if not OS.has_feature("rel") and not _ed:
		_ensure_zone_viz()
		_ensure_extra_zone_viz()
		_ensure_touch_point_viz()

	if _single_line:
		_ensure_grid_overlay()
	queue_redraw()
	background_rect_changed.emit()


var _cat_costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID


## 校验装扮编号并广播到所有格子，同时保留给之后创建的格子使用。
func set_cat_costume(costume_id: int) -> void:
	if not CostumeCatalog.is_valid(costume_id):
		return
	_cat_costume_id = costume_id
	if _cells.is_empty():
		return
	for row in _cells:
		for cell in row:
			(cell as CellView).set_cat_costume(costume_id)


## 把色盲图案开关和已填格保留规则广播到全部格子。
func set_pattern_mode(on: bool, keep_on_filled: bool) -> void:
	_pattern_on = on
	_pattern_keep_on_filled = keep_on_filled
	for row in _cells:
		for cell in row:
			(cell as CellView).set_pattern_mode(on, keep_on_filled)


var _cat_spine_pool: Array[SpineSprite] = []
## 本地修复：父棋盘先收到 PREDELETE，随后销毁的格子不能再把骨骼塞回已清空的池。
var _destroying: bool = false

const CAT_SPINE_PREWARM_MAX: int = 17

const _CAT_SPINE_PREWARM_SLACK: int = 2


## 按棋盘尺寸预建猫骨骼池，每创建两个实例让出一帧，最多保留预热目标 17 个。
func prewarm_cat_spines(size: int) -> void:
	if Engine.is_editor_hint() or size <= 0:
		return
	var want: int = mini(size + _CAT_SPINE_PREWARM_SLACK, CAT_SPINE_PREWARM_MAX)

	const PER_FRAME: int = 2
	var built: int = 0
	while _cat_spine_pool.size() < want:
		var spine := SpineSprite.new()
		spine.skeleton_data_res = CostumeSkin.SKELETON_RES
		_cat_spine_pool.append(spine)
		built += 1
		if built % PER_FRAME == 0:
			await get_tree().process_frame


## 取得或创建集中承载猫骨骼的 Node2D 层，供各格子的代理同步位置。
func ensure_cat_batch_layer() -> Node2D:
	var layer := get_node_or_null(NodePath(CellView.BATCH_LAYER_NAME)) as Node2D
	if layer != null:
		return layer
	layer = Node2D.new()
	layer.name = CellView.BATCH_LAYER_NAME

	layer.z_index = CellView.CAT_LAYER_Z_INDEX
	layer.z_as_relative = true
	add_child(layer)
	if layer.get_parent() == null:
		layer.free()
		return null
	return layer


## 从池尾取出首个仍有效的骨骼实例；池空时让调用者自行创建。
func acquire_pooled_cat_spine() -> SpineSprite:
	while not _cat_spine_pool.is_empty():
		var spine: SpineSprite = _cat_spine_pool.pop_back()
		if spine != null and is_instance_valid(spine):
			return spine
	return null


## 正常运行时卸下骨骼并回池；棋盘正在销毁时立即释放，避免留下无父节点的骨骼。
func recycle_cat_spine(spine: SpineSprite) -> void:
	if spine == null or not is_instance_valid(spine):
		return
	if _destroying:
		spine.free()
		return
	var parent: Node = spine.get_parent()
	if parent != null:
		parent.remove_child(spine)
	_cat_spine_pool.append(spine)


## 让各格子解除猫骨骼绑定并归还到棋盘池。
func release_cats_to_pool() -> void:
	for row in _cells:
		for cell in row:
			(cell as CellView).release_cat_spine()


## 棋盘销毁前释放池中未挂在场景树上的骨骼实例。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_destroying = true
		for spine in _cat_spine_pool:
			if spine != null and is_instance_valid(spine):
				spine.free()
		_cat_spine_pool.clear()


# ---- 分帧预热（避免一次性实例化太多格子卡帧） ----
const _PREWARM_CELLS_PER_FRAME: int = 4 # 每帧最多实例化 4 个格子


## 分帧预建格子节点，后续 setup 按名字复用；实际棋盘已经建立时停止预热。
func prewarm_cells(size: int) -> void:
	if size <= 0 or not _cells.is_empty():
		return

	if get_node_or_null("Cell_0_0") != null:
		return
	ensure_cat_batch_layer()
	_load_grid_ab(size)
	var built: int = 0
	for r in range(size):
		for c in range(size):
			if not _cells.is_empty():
				return
			var cell: CellView = _CELL_SCENE.instantiate() as CellView
			cell.position = Vector2(
				_grid_padding + c * _grid_slot + _grid_gap,
				_grid_padding + r * _grid_slot + _grid_gap,
			)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(cell)
			cell.name = "Cell_%d_%d" % [r, c]
			built += 1
			if built % _PREWARM_CELLS_PER_FRAME == 0:
				await get_tree().process_frame


# ================= 坐标换算 =================
## 对外查询：格子边长、格子矩形、格子中心，以及本地坐标 → 格子
func get_cell_size() -> int:
	return CELL_PX


## 返回当前布局中每格占用的槽位边长，单位为本地像素。
func get_grid_slot() -> int:
	return _grid_slot


## 返回当前棋盘四周留白，单位为本地像素。
func get_grid_padding() -> int:
	return _grid_padding


## 返回底面与槽位边缘之间的间隙，单位为本地像素。
func get_grid_gap() -> int:
	return _grid_gap


## 返回布局实验指定的格子底面边长。
func get_grid_cell_face_px() -> int:
	return _grid_cell_face_px


## 单线网格模式只让棋盘最外四角使用外框圆角，其余格子返回零掩码。
func corner_round_mask_for(r: int, c: int) -> int:
	var is_sl: bool = (
		not Engine.is_editor_hint()
		and ABTestManager != null
		and ABTestManager.game_grid_ui != null
		and ABTestManager.game_grid_ui.is_single_line()
	)
	if not is_sl:
		return 0
	var n: int = _puzzle_size
	if r == 0 and c == 0:
		return CellView.CORNER_TL
	if r == 0 and c == n - 1:
		return CellView.CORNER_TR
	if r == n - 1 and c == n - 1:
		return CellView.CORNER_BR
	if r == n - 1 and c == 0:
		return CellView.CORNER_BL
	return 0


## 缩放后的可见边长（像素）；当前全仓未被调用
func get_visible_cell_size() -> float:
	return CELL_PX * scale.x


## 返回背景圆角的设计像素值，绘制时还会按棋盘缩放补偿。
func get_board_background_corner_radius_px() -> float:
	return float(_grid_bg_corner)


## 取得当前背景底色；样式尚未建立时返回白色。
func get_board_background_color() -> Color:
	if _board_bg_style != null:
		return _board_bg_style.bg_color
	return Color.WHITE


## 返回背景在棋盘本地坐标中的矩形；编辑器预览使用居中的固有尺寸。
func get_board_background_rect_local() -> Rect2:
	var bg_size: Vector2 = size
	var bg_origin: Vector2 = Vector2.ZERO
	if Engine.is_editor_hint() and _puzzle_size > 0:
		bg_size = intrinsic_size_for(_puzzle_size)
		bg_origin = Vector2(
			maxf(0.0, (size.x - bg_size.x) * 0.5),
			maxf(0.0, (size.y - bg_size.y) * 0.5),
		)
	return Rect2(bg_origin, bg_size)


## 把行列换成格子的本地矩形，保留 CELL_PX 作为坐标基准尺寸。
func cell_to_local_rect(r: int, c: int) -> Rect2:
	return Rect2(
		_grid_padding + c * _grid_slot + _grid_gap,
		_grid_padding + r * _grid_slot + _grid_gap,
		CELL_PX,
		CELL_PX,
	)


## 在格子矩形外增加间隙，得到包含周围留白的槽位矩形。
func cell_to_local_slot_rect(r: int, c: int) -> Rect2:
	return cell_to_local_rect(r, c).grow(float(_grid_gap))


## (行,列) → 全局中心点（引导手势 / 粒子定位用）
func get_cell_global_center(r: int, c: int) -> Vector2:
	var local_rect: Rect2 = cell_to_local_rect(r, c)
	return global_position + local_rect.get_center() * scale


## 绘制棋盘圆角背景，并用缩放倒数补偿圆角半径。
func _draw() -> void:
	if _board_bg_style != null:
		var s: float = scale.x if scale.x > 0.0 else 1.0

		_board_bg_style.set_corner_radius_all(int(round(_grid_bg_corner / s)))

		draw_style_box(_board_bg_style, get_board_background_rect_local())
	if _puzzle_size == 0:
		return


## 向 CellView 提交状态变更；保护已落猫及答案位置，变化后发信号、记日志并刷新区域视觉。
## 成功落猫后还检查其他格子的猫与错标是否违反已知答案。
func set_cell_state(
	row: int,
	col: int,
	state: int,
	is_play_anim: bool = true,
	show_cat_visual: bool = true,
	source: int = ChangeSource.USER_ACTION,
	appear_anim: String = "",
	play_sound_with_custom_anim: bool = false,
	cat_spine_anim: String = "",
) -> void:
	if row < 0 or row >= _puzzle_size or col < 0 or col >= _puzzle_size:
		return
	if _cells.is_empty():
		return

	var cur: int = (_cells[row][col] as CellView).get_state()
	if cur == CellState.CAT and state != CellState.CAT:
		return
	if state == CellState.CAT:
		if (
			not _solution_cols.is_empty()
			and row < _solution_cols.size()
			and int(_solution_cols[row]) != col
		):
			push_error(
				(
					"[BoardView] set_cell_state CAT at non-solution cell (%d,%d), expected col=%d"
					% [row, col, int(_solution_cols[row])]
				)
			)
			return
		_last_cat_cell = Vector2i(row, col)
		_play_cat_vibrate(source)
	(
		(_cells[row][col] as CellView)
		. change_state(
			{
				"state": state,
				"play_anim": is_play_anim,
				"show_cat_visual": show_cat_visual,
				"appear_anim": appear_anim,
				"play_sound_with_custom_anim": play_sound_with_custom_anim,
				"cat_spine_anim": cat_spine_anim,
				"apply_eliminate_effect": _should_apply_eliminate_effect(source),
			}
		)
	)
	if cur != state:
		cell_state_changed.emit(row, col, state, source)
		_log_cell_change(row, col, cur, state, source)
		if state == CellState.CAT:
			_scan_and_heal_board_integrity(row, col)
			_try_play_grid_blast(row, col, source)

			var dim_animated: bool = (
				source != ChangeSource.PREFILL and source != ChangeSource.RESTORE
			)
			_refresh_region_dim_at(row, col, dim_animated)


## 对实际落猫反馈震动，预填与存档恢复不触发。
func _play_cat_vibrate(source: int) -> void:
	if source == ChangeSource.PREFILL or source == ChangeSource.RESTORE:
		return
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)


## 复制每行答案列号，供落猫和错标的完整性检查使用。
func set_solution(sol_1d: Array) -> void:
	_solution_cols = sol_1d.duplicate()


## 发现非答案猫或答案位置错标时恢复为空，发出 INTEGRITY_HEAL 来源的状态信号。
func _scan_and_heal_board_integrity(placed_r: int, placed_c: int) -> void:
	if _solution_cols.is_empty() or _cells.is_empty():
		return
	for r: int in range(_puzzle_size):
		for c: int in range(_puzzle_size):
			if r == placed_r and c == placed_c:
				continue
			var cell := _cells[r][c] as CellView
			var st: int = cell.get_state()
			if st != CellState.CAT and st != CellState.ERROR:
				continue
			var is_sol: bool = r < _solution_cols.size() and int(_solution_cols[r]) == c
			var violation: String = ""
			if st == CellState.CAT and not is_sol:
				violation = "CAT at non-solution cell (%d,%d)" % [r, c]
			elif st == CellState.ERROR and is_sol:
				violation = "ERROR at solution cell (%d,%d)" % [r, c]
			if violation.is_empty():
				continue
			push_error("[BoardView] board integrity violation: %s, healing to EMPTY" % violation)
			cell.change_state({"state": CellState.EMPTY})

			cell_state_changed.emit(r, c, CellState.EMPTY, ChangeSource.INTEGRITY_HEAL)
			_log_cell_change(r, c, st, CellState.EMPTY, ChangeSource.INTEGRITY_HEAL)

			_refresh_region_dim_at(r, c)


# ---- 只读查询接口（上层与手势识别器调用） ----
func get_puzzle_size() -> int:
	return _puzzle_size


## 直接返回区域二维数组，调用者应把它作为只读视图使用。
func get_regions() -> Array:
	return _regions


## 读单格状态；越界或未初始化返回 EMPTY
func get_cell_state(r: int, c: int) -> int:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return CellState.EMPTY
	return (_cells[r][c] as CellView).get_state()


## 查询该格是否已显示猫图像，区分逻辑落猫与延迟揭示。
func is_cat_visual_revealed(row: int, col: int) -> bool:
	var cell: CellView = get_cell_view(row, col)
	return cell != null and cell.is_cat_visual_revealed()


## 设置错标状态但不播放出现动画；保护锁定叉与答案位置，变化时发信号并记录来源。
func mark_cell_error(r: int, c: int, source: int = ChangeSource.USER_ACTION) -> void:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	var cur: int = (_cells[r][c] as CellView).get_state()

	if cur == CellState.LOCKED_MARK:
		return
	if not _solution_cols.is_empty() and r < _solution_cols.size() and int(_solution_cols[r]) == c:
		push_error("[BoardView] mark_cell_error at solution cell (%d,%d)" % [r, c])
		return
	(
		(_cells[r][c] as CellView)
		. change_state(
			{
				"state": CellState.ERROR,
				"play_anim": false,
				"apply_eliminate_effect": _should_apply_eliminate_effect(source),
			}
		)
	)
	if cur != CellState.ERROR:
		cell_state_changed.emit(r, c, CellState.ERROR, source)
		_log_cell_change(r, c, cur, CellState.ERROR, source)


## 设置并播放错标反馈；保护锁定叉与答案位置，变化时发信号并记录来源。
func play_error_feedback(r: int, c: int, source: int = ChangeSource.USER_ACTION) -> void:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	var cur: int = (_cells[r][c] as CellView).get_state()
	if cur == CellState.LOCKED_MARK:
		return
	if not _solution_cols.is_empty() and r < _solution_cols.size() and int(_solution_cols[r]) == c:
		push_error("[BoardView] play_error_feedback at solution cell (%d,%d)" % [r, c])
		return
	(
		(_cells[r][c] as CellView)
		. change_state(
			{
				"state": CellState.ERROR,
				"apply_eliminate_effect": _should_apply_eliminate_effect(source),
			}
		)
	)
	if cur != CellState.ERROR:
		cell_state_changed.emit(r, c, CellState.ERROR, source)
		_log_cell_change(r, c, cur, CellState.ERROR, source)


## 通关时重播全部猫的出现动画、恢复区域透明度，并按配置把红错标淡成白色。
func replay_all_cat_appear(cat_spine_anim: String = "") -> void:
	if _cells.is_empty():
		return

	if _region_dim_enabled:
		_reset_all_cell_dim(true)
	SoundManager.play(SoundManager.Kind.ALL_CLEARED)
	var fade_error_marks: bool = (
		ABTestManager.win_red_mark.should_fade_error_marks_to_white_on_win()
	)
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			var state: int = cell.get_state()
			if state == CellState.CAT:
				cell.force_play_appear(Vector2i(r, c) == _last_cat_cell, "", cat_spine_anim)
			elif fade_error_marks and state == CellState.ERROR:
				cell.play_win_error_mark_to_white()


## 让已有猫播放发现反馈，可排除一个指定的行列坐标。
func play_found_blink_all(anim_name: String = "", exclude: Vector2i = Vector2i(-1, -1)) -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if r == exclude.x and c == exclude.y:
				continue
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_found_blink(anim_name)


## 全盘猫进入「哭」循环（猜错时）
func play_cat_cry_loop_all() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_cry_loop()


## 全盘猫播一次沮丧表情
func play_cat_frustrated_all() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_frustrated_once()


## 全盘猫恢复 idle
func revive_all_cat_to_idle() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.revive_to_idle()


# ================= 棋盘导出 =================
## 导出完整状态棋盘（草稿 / 错标 / 锁定叉都是原值），交给规则引擎判定
func get_board() -> Array:
	var board: Array = []
	for r in range(_puzzle_size):
		var row: Array[int] = []
		row.resize(_puzzle_size)
		for c in range(_puzzle_size):
			row[c] = (_cells[r][c] as CellView).get_state()
		board.append(row)
	return board


## 导出规则简化棋盘：错标和锁定叉折为普通叉，草稿折为空格。
func get_cell_state_folded_board() -> Array:
	var board: Array = []
	for r in range(_puzzle_size):
		var row: Array[int] = []
		row.resize(_puzzle_size)
		for c in range(_puzzle_size):
			var s: int = (_cells[r][c] as CellView).get_state()
			if s == CellState.ERROR or s == CellState.LOCKED_MARK:
				row[c] = CellState.MARK
			elif CellState.is_draft(s):
				row[c] = CellState.EMPTY
			else:
				row[c] = s
		board.append(row)
	return board


# ================= 统计与查询 =================
## 单格是否错标
func is_cell_error(r: int, c: int) -> bool:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return false
	return (_cells[r][c] as CellView).get_state() == CellState.ERROR


## 错标格数量
func count_error_cells() -> int:
	return _count_cells_in_state(CellState.ERROR)


## 叉数量（普通叉 + 锁定叉）
func count_mark_cells() -> int:
	return _count_cells_in_state(CellState.MARK) + _count_cells_in_state(CellState.LOCKED_MARK)


## 空格数量（空 + 草稿，与 CellState.is_blank 一致）
func count_empty_cells() -> int:
	if _cells.is_empty():
		return 0
	var n: int = 0
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if CellState.is_blank((_cells[r][c] as CellView).get_state()):
				n += 1
	return n


## 按已找到猫的数量选择爆破档位，恢复与预填过程不触发粒子效果。
func _try_play_grid_blast(row: int, col: int, source: int) -> void:
	if Engine.is_editor_hint():
		return
	if source == ChangeSource.PREFILL or source == ChangeSource.RESTORE:
		return
	if ABTestManager == null:
		return
	var cfg: GridBlastConfig = ABTestManager.grid_blast
	if cfg == null:
		return
	var tier: int = cfg.blast_tier(count_cat_cells(), _puzzle_size)
	if tier <= 0:
		return
	(_cells[row][col] as CellView).play_grid_blast(tier)


## 猫数量
func count_cat_cells() -> int:
	return _count_cells_in_state(CellState.CAT)


## 按状态统计格子数（未初始化返回 0）
func _count_cells_in_state(state: int) -> int:
	if _cells.is_empty():
		return 0
	var n: int = 0
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if (_cells[r][c] as CellView).get_state() == state:
				n += 1
	return n


## 取单格区域底色（区域表为空或越界返回白色）
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


## 取单格 CellView 节点；越界或未初始化返回 null
func get_cell_view(r: int, c: int) -> CellView:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return null
	return _cells[r][c] as CellView


## 对已有猫请求追加濒危出现动画。
func play_near_death_appear(r: int, c: int) -> void:
	var cell := get_cell_view(r, c)
	if cell == null or cell.get_state() != CellState.CAT:
		return
	cell.play_near_death_appear()


## 把已落猫但隐藏的格子交给 CellView 揭示，可附加粒子与光晕。
func reveal_hidden_cat(
	r: int,
	c: int,
	appear_anim: String = "CatIconAppear",
	with_particles: bool = false,
	with_halo: bool = false,
) -> void:
	var cell: CellView = get_cell_view(r, c)
	if cell == null:
		return
	cell.reveal_hidden_cat(appear_anim, with_particles, with_halo)


## 在指定格子播放预填猫爪动画，并传入水平翻转选项。
func play_pre_cat_paw(r: int, c: int, flip: bool = false) -> void:
	var cell: CellView = get_cell_view(r, c)
	if cell == null:
		return
	cell.play_pre_cat_paw(flip)


## 把本地像素坐标换为 Vector2i(列, 行)；棋盘外返回 (-1, -1)，与状态数组的行列顺序不同。
func pointer_to_cell(px: float, py: float) -> Vector2i:
	if _puzzle_size == 0:
		return Vector2i(-1, -1)
	var col: int = floori((px - _grid_padding) / _grid_slot)
	var row: int = floori((py - _grid_padding) / _grid_slot)
	if row < 0 or row >= _puzzle_size or col < 0 or col >= _puzzle_size:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


## 判断触点是否落在棋盘控件向四周扩展 slop_px 后的命中范围。
func is_pos_in_extended_hit_area(local_pos: Vector2, slop_px: float) -> bool:
	return Rect2(-slop_px, -slop_px, size.x + slop_px * 2.0, size.y + slop_px * 2.0).has_point(
		local_pos
	)


## 按棋盘位置与统一缩放把全局触点换为本地坐标。
func to_local_touch_pos(global_pos: Vector2) -> Vector2:
	var s: float = scale.x if scale.x > 0.0 else 1.0
	return (global_pos - global_position) / s


## 把手势锁定数据交给调试层，开启可视化时同时记录变化。
func update_swipe_protection_zone(lock: Dictionary) -> void:
	if _zone_viz != null and is_instance_valid(_zone_viz):
		_zone_viz.set_zone(lock)
	if _swipe_viz_on:
		_log_zone_change_if_needed(lock)


## 只在锁定内容变化时输出保护区日志，避免每帧重复打印。
func _log_zone_change_if_needed(lock: Dictionary) -> void:
	if lock == _last_logged_lock:
		return
	_last_logged_lock = lock.duplicate() if not lock.is_empty() else {}
	if lock.is_empty():
		print("[swipe_viz] 保护解除")
		return
	var pad: int = _grid_padding
	var slot: int = _grid_slot
	var extent: int = pad * 2 + slot * _puzzle_size
	if not lock.has("axis"):
		return
	_log_axis_lock(lock, pad, slot, extent)


## 同时格式化本地与屏幕矩形，方便核对可视范围。
func _rect_str(tl_local: Vector2i, br_local: Vector2i) -> String:
	var tl_scr: Vector2i = _local_to_screen(Vector2(tl_local))
	var br_scr: Vector2i = _local_to_screen(Vector2(br_local))
	return (
		"screen TL=(%d, %d) BR=(%d, %d)  (local TL=(%d, %d) BR=(%d, %d))"
		% [tl_scr.x, tl_scr.y, br_scr.x, br_scr.y, tl_local.x, tl_local.y, br_local.x, br_local.y]
	)


## 组合节点画布与视口屏幕变换，将本地位置换为屏幕整数像素。
func _local_to_screen(local: Vector2) -> Vector2i:
	var canvas_xform: Transform2D = get_global_transform_with_canvas()
	var screen_xform: Transform2D = get_viewport().get_screen_transform()
	return Vector2i((screen_xform * canvas_xform * local).round())


## 输出当前锁定的行列、核心矩形与容错带。
func _log_axis_lock(lock: Dictionary, pad: int, slot: int, extent: int) -> void:
	var is_row: bool = lock["axis"] == SwipeAxisGuard.Axis.ROW
	var axis_str: String = "ROW" if is_row else "COL"
	var val: int = lock["value"]
	var tol: float = lock.get("tol", 0.0)
	var core0: int = pad + val * slot
	var core1: int = pad + (val + 1) * slot
	var band0: int = int(core0 - tol)
	var band1: int = int(core1 + tol)

	var core_tl: Vector2i
	var core_br: Vector2i
	var band_tl: Vector2i
	var band_br: Vector2i
	if is_row:
		core_tl = Vector2i(0, core0)
		core_br = Vector2i(extent, core1)
		band_tl = Vector2i(0, band0)
		band_br = Vector2i(extent, band1)
	else:
		core_tl = Vector2i(core0, 0)
		core_br = Vector2i(core1, extent)
		band_tl = Vector2i(band0, 0)
		band_br = Vector2i(band1, extent)

	var cells: Array[String] = []
	for i: int in _puzzle_size:
		if is_row:
			cells.append("(%d,%d)" % [i, val])
		else:
			cells.append("(%d,%d)" % [val, i])
	print(
		(
			"[swipe_viz] axis=%s value=%d tol=%.0fpx  锁 %d 格: %s"
			% [axis_str, val, tol, cells.size(), ", ".join(cells)]
		)
	)
	print("[swipe_viz]   核心矩形:      %s" % _rect_str(core_tl, core_br))
	print("[swipe_viz]   容差带矩形:    %s  (核心 ±tol=%.0fpx)" % [_rect_str(band_tl, band_br), tol])


## 切换行列保护区调试显示，并清空日志去重状态。
func toggle_swipe_zone_viz() -> bool:
	_swipe_viz_on = not _swipe_viz_on
	if _zone_viz != null and is_instance_valid(_zone_viz):
		_zone_viz.set_enabled(_swipe_viz_on)

	_last_logged_lock = {}
	return _swipe_viz_on


## 创建或复用行列保护调试层，更新布局、区域图与显示状态。
func _ensure_zone_viz() -> void:
	if _zone_viz == null or not is_instance_valid(_zone_viz) or not _zone_viz.is_inside_tree():
		_zone_viz = SwipeZoneDebugOverlay.new()
		_zone_viz.name = "SwipeZoneViz"
		add_child(_zone_viz)
	_zone_viz.configure(_grid_slot, _grid_padding, _puzzle_size)

	_zone_viz.set_regions(_regions)
	_zone_viz.set_enabled(_swipe_viz_on)


## 切换棋盘外扩命中范围的调试显示。
func toggle_swipe_extra_zone_viz() -> bool:
	_extra_zone_viz_on = not _extra_zone_viz_on
	if _extra_zone_viz != null and is_instance_valid(_extra_zone_viz):
		_extra_zone_viz.set_enabled(_extra_zone_viz_on)
	return _extra_zone_viz_on


## 把最新额外容错距离交给调试层。
func update_swipe_extra_zone_slop(slop_px: float) -> void:
	if _extra_zone_viz != null and is_instance_valid(_extra_zone_viz):
		_extra_zone_viz.refresh(slop_px)


## 创建或复用外扩命中范围调试层，并同步棋盘布局。
func _ensure_extra_zone_viz() -> void:
	if (
		_extra_zone_viz == null
		or not is_instance_valid(_extra_zone_viz)
		or not _extra_zone_viz.is_inside_tree()
	):
		_extra_zone_viz = SwipeExtraZoneDebugOverlay.new()
		_extra_zone_viz.name = "SwipeExtraZoneViz"
		add_child(_extra_zone_viz)
	_extra_zone_viz.configure(_grid_slot, _grid_padding, _puzzle_size)
	_extra_zone_viz.set_enabled(_extra_zone_viz_on)


## 切换触点调试圆的显示。
func toggle_touch_point_viz() -> bool:
	_touch_point_viz_on = not _touch_point_viz_on
	if _touch_point_viz != null and is_instance_valid(_touch_point_viz):
		_touch_point_viz.set_enabled(_touch_point_viz_on)
	return _touch_point_viz_on


## 供输入处理层判断是否需要更新触点调试数据。
func is_touch_point_viz_on() -> bool:
	return _touch_point_viz_on


## 转交棋盘本地坐标中的触点列表。
func update_touch_points(points: Array[Vector2]) -> void:
	if _touch_point_viz != null and is_instance_valid(_touch_point_viz):
		_touch_point_viz.update_points(points)


## 创建或复用触点调试层，并应用当前开关。
func _ensure_touch_point_viz() -> void:
	if (
		_touch_point_viz == null
		or not is_instance_valid(_touch_point_viz)
		or not _touch_point_viz.is_inside_tree()
	):
		_touch_point_viz = TouchPointDebugOverlay.new()
		_touch_point_viz.name = "TouchPointViz"
		add_child(_touch_point_viz)
	_touch_point_viz.set_enabled(_touch_point_viz_on)


# ================= 提示高亮 =================
## 设置提示高亮：与上一批求差集，新增的闪起来、移除的收起来
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


## 清掉全部提示高亮
func clear_hint_cells() -> void:
	for cell in _hint_unit_cells:
		(_cells[cell.x][cell.y] as CellView).play_hide_hint()
	_hint_unit_cells = []
	_hint_key_cell = Vector2i(-1, -1)
	queue_redraw()


# ================= 区域色查询 =================
## 区域号 → 调色板下标（越界时取模）
func get_region_color_index(region_idx: int) -> int:
	if region_idx < _color_map.size():
		return _color_map[region_idx] % _region_colors.size()
	return region_idx % _region_colors.size()


## 区域号 → 颜色（下标越界返回白色）
func get_region_color(region_idx: int) -> Color:
	var ci: int = get_region_color_index(region_idx)
	if ci < _region_colors.size():
		return _region_colors[ci]
	return Color.WHITE


## 开启时按区域建立索引并刷新透明度；关闭时清空索引、恢复全部格子。
func set_region_dim_enabled(on: bool, animated: bool = false) -> void:
	_region_dim_enabled = on
	if not on:
		_region_cells.clear()
		_reset_all_cell_dim(animated)
		return
	_rebuild_region_cell_index()

	_refresh_all_region_dim(animated)


## 按当前落猫状态重新计算所有区域的透明度。
func refresh_all_region_dim() -> void:
	_refresh_all_region_dim()


## 把区域二维图转换为区域号到行列坐标列表的索引。
func _rebuild_region_cell_index() -> void:
	_region_cells.clear()
	if _regions.is_empty() or _cells.is_empty():
		return
	for r in _puzzle_size:
		for c in _puzzle_size:
			var region_idx: int = int(_regions[r][c])
			if not _region_cells.has(region_idx):
				_region_cells[region_idx] = []
			var region_cell_list: Array = _region_cells[region_idx]
			region_cell_list.append(Vector2i(r, c))


## 只刷新给定格子所属的区域，避免每次落猫全盘重算。
func _refresh_region_dim_at(r: int, c: int, animated: bool = false) -> void:
	if not _region_dim_enabled or _regions.is_empty():
		return
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	_refresh_region_dim(int(_regions[r][c]), animated)


## 区域中已有猫时，对该区域全部格子应用实验指定的透明度。
func _refresh_region_dim(region_idx: int, animated: bool = false) -> void:
	if not _region_dim_enabled or Engine.is_editor_hint():
		return
	if _cells.is_empty() or not _region_cells.has(region_idx) or ABTestManager == null:
		return
	var region_cell_list: Array = _region_cells[region_idx]
	var has_cat: bool = false
	for pos: Vector2i in region_cell_list:
		if (_cells[pos.x][pos.y] as CellView).get_state() == CellState.CAT:
			has_cat = true
			break
	var dim: float = (
		ABTestManager.cat_found_grid.dim_alpha() if has_cat else CatFoundGridConfig.ALPHA_NONE
	)
	for pos: Vector2i in region_cell_list:
		(_cells[pos.x][pos.y] as CellView).set_dim_alpha(dim, animated)


## 遍历已缓存的区域编号，刷新各区域淡化状态。
func _refresh_all_region_dim(animated: bool = false) -> void:
	if not _region_dim_enabled:
		return
	var region_ids: Array = _region_cells.keys()
	for rid in region_ids:
		_refresh_region_dim(int(rid), animated)


## 把全部格子的区域淡化恢复为正常值，可带过渡动画。
func _reset_all_cell_dim(animated: bool = false) -> void:
	for row: Array in _cells:
		for cell: CellView in row:
			cell.set_dim_alpha(CatFoundGridConfig.ALPHA_NONE, animated)


## 停止全部格子的爆破粒子，避免换题残留。
func _reset_all_cell_grid_blast() -> void:
	for row: Array in _cells:
		for cell: CellView in row:
			cell.reset_grid_blast()


## 该格所属区域共有几格
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


## 该格所属区域里是否出现过叉（R4+ 鼓掌提示的前置条件）
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


## 该格所属区域里是否出现过错标
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
## 指定格播 R2 预览动画
func play_r2_preview_cell(r: int, c: int) -> void:
	if r >= 0 and r < _cells.size() and c >= 0 and c < (_cells[r] as Array).size():
		(_cells[r][c] as CellView).play_r2_preview()


## 同上，可延迟若干秒（多格排队预览）
func play_r2_preview_cell_delayed(r: int, c: int, delay: float) -> void:
	if r >= 0 and r < _cells.size() and c >= 0 and c < (_cells[r] as Array).size():
		(_cells[r][c] as CellView).play_r2_preview(delay)


# ================= 坐标数字 =================
## 切换行列坐标数字；状态写回 GameState 以便跨局保留
func toggle_coords() -> void:
	_coord_visible = not _coord_visible
	GameState.coords_visible = _coord_visible
	for lbl in _coord_labels:
		lbl.visible = _coord_visible


## 按当前槽位和边距重建一基行列编号，并沿用显示开关。
func _rebuild_coord_labels() -> void:
	for lbl in _coord_labels:
		lbl.queue_free()
	_coord_labels = []
	if _puzzle_size == 0:
		return
	var ox: int = _grid_padding
	var oy: int = _grid_padding

	for c in range(_puzzle_size):
		var lbl := Label.new()
		lbl.text = str(c + 1)
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.85))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(_grid_slot, 44)
		lbl.position = Vector2(ox + c * _grid_slot, oy - 46)
		lbl.visible = _coord_visible
		add_child(lbl)
		_coord_labels.append(lbl)

	for r in range(_puzzle_size):
		var lbl := Label.new()
		lbl.text = str(r + 1)
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.85))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(44, _grid_slot)
		lbl.position = Vector2(ox - 48, oy + r * _grid_slot)
		lbl.visible = _coord_visible
		add_child(lbl)
		_coord_labels.append(lbl)


## 把当前棋盘缩放与尺寸传给每格，补偿实际显示的圆角。
func apply_compensated_cell_corner_radius() -> void:
	if scale.x <= 0.0:
		return
	if _cells.is_empty():
		return
	for row in _cells:
		for cell in row:
			if cell is CellView:
				(cell as CellView).set_corner_radius_compensated(scale.x, _puzzle_size)


## 创建或复用单线网格层，将其移到格子上方并更新区域边界。
func _ensure_grid_overlay() -> void:
	if (
		_grid_overlay == null
		or not is_instance_valid(_grid_overlay)
		or not _grid_overlay.is_inside_tree()
	):
		_grid_overlay = BoardGridOverlay.new()
		_grid_overlay.name = "GridOverlay"
		_grid_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_overlay.board = self
		add_child(_grid_overlay)
		if Engine.is_editor_hint():
			_grid_overlay.owner = null
	move_child(_grid_overlay, get_child_count() - 1)
	_grid_overlay.configure(_regions, _puzzle_size)


## 按需创建区域填色与发光层，并显示目标区域轮廓。
func show_region_highlight(region_id: int) -> void:
	if _cells.is_empty() or region_id < 0:
		return
	if (
		_region_highlight == null
		or not is_instance_valid(_region_highlight)
		or not _region_highlight.is_inside_tree()
	):
		var glow_layer: Node2D = Node2D.new()
		glow_layer.name = "RegionHighlightGlow"
		glow_layer.z_index = RegionHighlightOverlay.GLOW_Z_INDEX
		glow_layer.z_as_relative = true
		add_child(glow_layer)
		_region_highlight = RegionHighlightOverlay.new()
		_region_highlight.name = "RegionHighlight"
		_region_highlight.board = self
		_region_highlight.glow_layer = glow_layer
		add_child(_region_highlight)
	move_child(_region_highlight, 0)
	_region_highlight.show_region(region_id)


## 请求当前区域高亮淡出。
func stop_region_highlight() -> void:
	if _region_highlight != null and is_instance_valid(_region_highlight):
		_region_highlight.stop()


## 返回当前高亮区域编号，没有高亮层时返回 -1。
func highlighted_region() -> int:
	if _region_highlight != null and is_instance_valid(_region_highlight):
		return _region_highlight.showing_region()
	return -1


## 把棋盘入场时长交给网格层，开始同步的格线生长动画。
func on_board_entry_started(sync_total_dur: float = 0.0) -> void:
	if _grid_overlay != null and is_instance_valid(_grid_overlay):
		_grid_overlay.begin_grid_intro(sync_total_dur)


## 重置全部定时锁并更新手动锁；递增令牌使旧定时器的回调失效。
func set_touch_enabled(enabled: bool) -> void:
	_touch_token += 1
	_touch_timed_lock_count = 0
	_touch_yielding_lock_count = 0
	_touch_manual_locked = not enabled
	_refresh_touch_enabled()


## 返回合并手动锁与定时锁后的当前输入状态。
func is_touch_enabled() -> bool:
	return _touch_enabled


## 叠加一个定时输入锁；到期且令牌仍有效时释放，可标记为允许待处理双击让步的锁。
func disable_touch_for(sec: float, yields_to_pending_double_tap: bool = false) -> void:
	_touch_timed_lock_count += 1
	if yields_to_pending_double_tap:
		_touch_yielding_lock_count += 1
	_refresh_touch_enabled()
	if Engine.is_editor_hint():
		return
	var tok: int = _touch_token
	get_tree().create_timer(sec).timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return

			if tok != _touch_token:
				return
			_touch_timed_lock_count -= 1
			if yields_to_pending_double_tap:
				_touch_yielding_lock_count -= 1
			_refresh_touch_enabled()
	)


## 只有全部现存定时锁都允许让步且没有手动锁时，输入层才可处理待定双击。
func is_locked_only_by_yielding_locks() -> bool:
	if _touch_manual_locked or _touch_timed_lock_count == 0:
		return false
	return _touch_timed_lock_count == _touch_yielding_lock_count


## 仅在没有手动锁、也没有定时锁时启用棋盘输入。
func _refresh_touch_enabled() -> void:
	_touch_enabled = not _touch_manual_locked and _touch_timed_lock_count == 0


## 在棋盘有效格内接收鼠标左键起点，并发出本地坐标的拖动开始与结束信号。
func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if not _touch_enabled:
		_dragging = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if pointer_to_cell(mb.position.x, mb.position.y).x >= 0:
					_dragging = true
					cell_drag_start.emit(mb.position)
				else:
					_dragging = false
			else:
				_dragging = false
				cell_drag_end.emit(mb.position)


## 拖动已开始且左键仍按住时，把鼠标移动转为棋盘本地坐标信号。
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _touch_enabled:
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if not _dragging:
				return
			var local_pos: Vector2 = (make_input_local(mm) as InputEventMouseMotion).position
			cell_drag_over.emit(local_pos)


## 从 9×9 一级题库取首题建立编辑器预览，并监听尺寸变化重新居中。
func _render_editor_preview() -> void:
	var levels: Array = BankData.get_levels(9, 1)
	if levels.is_empty():
		push_warning("BoardView: editor_preview 未取到 9x9 题库(bankData9x9.json rank 1)")
		return
	var entry: Dictionary = levels[0]
	var raw_regions: Array = BankData.get_region_map(entry)
	if raw_regions.is_empty():
		push_warning("BoardView: editor_preview 题目缺 regionMap")
		return

	var int_regions: Array = []
	for row_arr: Array in raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)
	var sz: int = int_regions.size()
	var color_map: Array[int] = LevelGenerator.compute_color_map_with_seed(sz, int_regions, 0)
	setup(sz, int_regions, color_map)

	if not resized.is_connected(_relayout_editor_preview_cells):
		resized.connect(_relayout_editor_preview_cells)
	_relayout_editor_preview_cells()


## 在编辑器控件中居中摆放预览格子，再通知背景几何变化。
func _relayout_editor_preview_cells() -> void:
	if _puzzle_size == 0 or _cells.is_empty():
		return
	var intrinsic: Vector2 = intrinsic_size_for(_puzzle_size)
	var offset_x: float = maxf(0.0, (size.x - intrinsic.x) * 0.5)
	var offset_y: float = maxf(0.0, (size.y - intrinsic.y) * 0.5)
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell: CellView = _cells[r][c]
			if cell == null:
				continue
			cell.position = Vector2(
				_grid_padding + c * _grid_slot + _grid_gap + offset_x,
				_grid_padding + r * _grid_slot + _grid_gap + offset_y,
			)
	queue_redraw()
	background_rect_changed.emit()


## 断开预览布局监听并释放子节点，清空棋盘视图数据。
func _clear_editor_preview() -> void:
	if resized.is_connected(_relayout_editor_preview_cells):
		resized.disconnect(_relayout_editor_preview_cells)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cells = []
	_coord_labels = []
	_puzzle_size = 0
	_grid_overlay = null
	queue_redraw()
	background_rect_changed.emit()


var _batch_log_pending: Dictionary = {}

var _batch_log_queued: bool = false


## 恢复、预填与自动完成合并为批次日志；普通变化和完整性修复分别发送事件。
func _log_cell_change(r: int, c: int, from_state: int, to_state: int, source: int) -> void:
	if Engine.is_editor_hint():
		return
	match source:
		ChangeSource.RESTORE, ChangeSource.PREFILL, ChangeSource.AUTO_COMPLETE:
			_batch_log_pending[source] = int(_batch_log_pending.get(source, 0)) + 1
			if not _batch_log_queued:
				_batch_log_queued = true
				call_deferred("_flush_batch_log")
		ChangeSource.INTEGRITY_HEAL:
			(
				EventBus
				. emit_event(
					EventName.GAME_BOARD_HEAL,
					{
						"r": r,
						"c": c,
						"from": CellState.name_of(from_state),
					}
				)
			)
		_:
			(
				EventBus
				. emit_event(
					EventName.GAME_CELL,
					{
						"r": r,
						"c": c,
						"from": CellState.name_of(from_state),
						"to": CellState.name_of(to_state),
						"src": source_name(source),
					}
				)
			)


## 输出本轮各来源累计改变的格数，并清空待发送计数。
func _flush_batch_log() -> void:
	_batch_log_queued = false
	if _batch_log_pending.is_empty():
		return
	for src in _batch_log_pending:
		(
			EventBus
			. emit_event(
				EventName.GAME_BOARD_BATCH,
				{
					"src": source_name(int(src)),
					"cells": int(_batch_log_pending[src]),
				}
			)
		)
	_batch_log_pending.clear()


## 把状态变更来源枚举转换成日志使用的稳定字符串。
static func source_name(src: int) -> String:
	match src:
		ChangeSource.USER_ACTION:
			return "user_action"
		ChangeSource.RESTORE:
			return "restore"
		ChangeSource.LOCATE:
			return "locate"
		ChangeSource.HINT:
			return "hint"
		ChangeSource.UNDO:
			return "undo"
		ChangeSource.PREFILL:
			return "prefill"
		ChangeSource.AUTO_COMPLETE:
			return "auto_complete"
		ChangeSource.DRAFT_APPLY:
			return "draft_apply"
		ChangeSource.INTEGRITY_HEAL:
			return "integrity_heal"
		ChangeSource.MOUSE:
			return "mouse"
		ChangeSource.DRAFT_ROLLBACK:
			return "draft_rollback"
		ChangeSource.FULL_MARK_AUTO_CROSS:
			return "full_mark_auto_cross"
	return "unknown(%d)" % src
