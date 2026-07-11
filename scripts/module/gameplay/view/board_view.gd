@tool
class_name BoardView
extends Control

const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")
const _AUTO_MARK_BTN_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/auto_mark_btn.tscn"
)
const BOARD_PADDING: int = 15
const CELL_PX: int = 100
const CELL_GAP: int = 4
const SLOT_PX: int = CELL_PX + 2 * CELL_GAP

const BOARD_BG_CORNER_RADIUS: int = 30

const _AUTO_MARK_BTN_W: float = 25.0
const _AUTO_MARK_BTN_H: float = 20.0
const _AUTO_MARK_BTN_OUT_GAP: float = 25.0

enum ChangeSource {
	USER_ACTION, RESTORE, LOCATE, HINT, UNDO, AUTOMARK, PREFILL, AUTO_COMPLETE, DRAFT_APPLY
}


static func intrinsic_size_for(sz: int) -> Vector2:
	var n: int = SLOT_PX * sz + BOARD_PADDING * 2
	return Vector2(n, n)


var _puzzle_size: int = 0
var _regions: Array = []
var _color_map: Array[int] = []
var _region_colors: PackedColorArray = PackedColorArray()
var _cells: Array = []

var _hint_unit_cells: Array[Vector2i] = []
var _hint_key_cell: Vector2i = Vector2i(-1, -1)
var _last_cat_cell: Vector2i = Vector2i(-1, -1)
var _coord_visible: bool = false
var _coord_labels: Array[Label] = []

var _row_auto_mark_btns: Array = []
var _col_auto_mark_btns: Array = []

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

var _board_bg_style: StyleBoxFlat = null

var _dragging: bool = false

var _swipe_viz_on: bool = false
var _zone_viz: SwipeZoneDebugOverlay = null

signal cell_drag_start(pos: Vector2)
signal cell_drag_over(pos: Vector2)
signal cell_drag_end

signal cell_state_changed(row: int, col: int, state: int, source: int)

signal axis_auto_mark_pressed(axis: int, idx: int, is_marked_before: bool)


func _ready() -> void:
	_board_bg_style = StyleBoxFlat.new()
	_board_bg_style.bg_color = Color(1, 1, 1, 1)

	if Engine.is_editor_hint():
		if editor_preview:
			_render_editor_preview()
		return
	_coord_visible = GameState.coords_visible


static func resolve_region_palette() -> PackedColorArray:
	var temp_cell: CellView = _CELL_SCENE.instantiate() as CellView
	var pal: PackedColorArray = temp_cell.region_colors
	temp_cell.free()

	if Engine.is_editor_hint():
		return pal
	if ABTestManager.region_color.is_custom_palette():
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
	if ABTestManager.region_color.is_new_cell_only_palette():
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
	if ABTestManager.region_color.is_cell_color_v3():
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
	return pal


func setup(
	puzzle_size: int,
	regions: Array,
	color_map: Array[int],
	pattern_regions: Array = [],
	recycle_reused: bool = false
) -> void:
	_puzzle_size = puzzle_size
	_regions = regions
	_color_map = color_map

	_dragging = false

	_hint_unit_cells = []
	_hint_key_cell = Vector2i(-1, -1)
	_last_cat_cell = Vector2i(-1, -1)

	_region_colors = resolve_region_palette()

	var _ed: bool = Engine.is_editor_hint()

	if not _ed and ABTestManager.region_color.is_cell_color_v3():
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
	elif not _ed and ABTestManager.region_color.is_new_cell_recompute():
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
	elif not _ed and ABTestManager.region_color.is_palette_v5():
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
	elif not _ed and ABTestManager.region_color.is_palette_v7():
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
		remove_child(child)
		child.queue_free()
	_cells = []
	_coord_labels = []

	for r in range(puzzle_size):
		var row: Array = []
		for c in range(puzzle_size):
			var key: String = "Cell_%d_%d" % [r, c]
			var cell: CellView = prebaked.get(key) as CellView
			if cell == null:
				cell = _CELL_SCENE.instantiate() as CellView
				cell.position = Vector2(
					BOARD_PADDING + c * SLOT_PX + CELL_GAP,
					BOARD_PADDING + r * SLOT_PX + CELL_GAP,
				)

				add_child(cell)

				cell.name = key
			elif recycle_reused:
				cell._reset_to_empty_baseline()

			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var region_idx: int = _regions[r][c]
			var ci: int = (
				_color_map[region_idx]
				if region_idx < _color_map.size()
				else (region_idx % _region_colors.size())
			)
			ci = ci % _region_colors.size()
			cell.set_region_color(_region_colors[ci])

			cell.reset_clap_tracking()

			cell.set_auto_mark_locked(false)
			row.append(cell)
		_cells.append(row)

	apply_compensated_cell_corner_radius()

	_rebuild_coord_labels()
	_rebuild_auto_mark_btns()

	if not OS.has_feature("rel") and not _ed:
		_ensure_zone_viz()
	queue_redraw()


const _PREWARM_CELLS_PER_FRAME: int = 4


func prewarm_cells(size: int) -> void:
	if size <= 0 or not _cells.is_empty():
		return
	if get_node_or_null("Cell_0_0") != null:
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
			if built % _PREWARM_CELLS_PER_FRAME == 0:
				await get_tree().process_frame


func get_cell_size() -> int:
	return CELL_PX


func get_visible_cell_size() -> float:
	return CELL_PX * scale.x


func cell_to_local_rect(r: int, c: int) -> Rect2:
	return Rect2(
		BOARD_PADDING + c * SLOT_PX + CELL_GAP,
		BOARD_PADDING + r * SLOT_PX + CELL_GAP,
		CELL_PX,
		CELL_PX,
	)


func get_cell_global_center(r: int, c: int) -> Vector2:
	var local_rect: Rect2 = cell_to_local_rect(r, c)
	return global_position + local_rect.get_center() * scale


func _draw() -> void:
	if _board_bg_style != null:
		var s: float = scale.x if scale.x > 0.0 else 1.0
		_board_bg_style.set_corner_radius_all(int(round(BOARD_BG_CORNER_RADIUS / s)))

		var bg_size: Vector2 = size
		var bg_origin: Vector2 = Vector2.ZERO
		if Engine.is_editor_hint() and _puzzle_size > 0:
			bg_size = intrinsic_size_for(_puzzle_size)
			bg_origin = Vector2(
				maxf(0.0, (size.x - bg_size.x) * 0.5),
				maxf(0.0, (size.y - bg_size.y) * 0.5),
			)
		draw_style_box(_board_bg_style, Rect2(bg_origin, bg_size))
	if _puzzle_size == 0:
		return


func set_cell_state(
	r: int,
	c: int,
	state: int,
	is_play_anim: bool = true,
	show_cat_visual: bool = true,
	source: int = ChangeSource.USER_ACTION,
	split_press: bool = false
) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	if _cells.is_empty():
		return

	var cur: int = (_cells[r][c] as CellView).get_state()
	if cur == CellState.CAT and state != CellState.CAT:
		return

	if cur == CellState.LOCKED_MARK:
		return
	if state == CellState.CAT:
		_last_cat_cell = Vector2i(r, c)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
	(_cells[r][c] as CellView).change_state(
		{
			"state": state,
			"play_anim": is_play_anim,
			"show_cat_visual": show_cat_visual,
			"split_press": split_press
		}
	)
	if cur != state:
		cell_state_changed.emit(r, c, state, source)


func play_mark_release(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	(_cells[r][c] as CellView).play_mark_release()


func play_auto_cross(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	if (_cells[r][c] as CellView).get_state() != CellState.EMPTY:
		return
	(_cells[r][c] as CellView).change_state(
		{"state": CellState.MARK, "play_anim": true, "appear_anim": "AutomaticAppear"}
	)
	cell_state_changed.emit(r, c, CellState.MARK, ChangeSource.AUTOMARK)


func preset_auto_cross(r: int, c: int) -> bool:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return false
	var cell: CellView = _cells[r][c] as CellView
	if cell.get_state() != CellState.EMPTY:
		return false
	cell.preset_mark_for_auto_cross()
	cell_state_changed.emit(r, c, CellState.MARK, ChangeSource.AUTOMARK)
	return true


func play_pending_auto_cross_appear(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	(_cells[r][c] as CellView).play_pending_auto_cross_appear()


func play_auto_uncross(r: int, c: int) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	var cell: CellView = _cells[r][c] as CellView
	if cell.get_state() != CellState.MARK:
		return
	cell.change_state(
		{"state": CellState.EMPTY, "play_anim": true, "disappear_anim": "AutomaticDisappear"}
	)
	cell_state_changed.emit(r, c, CellState.EMPTY, ChangeSource.AUTOMARK)


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
	if cell.get_state() != CellState.MARK:
		return
	cell.change_state(
		{"state": CellState.LOCKED_MARK, "play_anim": play_anim, "lock_anim": lock_anim}
	)
	cell_state_changed.emit(r, c, CellState.LOCKED_MARK, source)


func set_cell_input_locked(r: int, c: int, locked: bool) -> void:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return
	(_cells[r][c] as CellView).set_auto_mark_locked(locked)


func is_cell_input_locked(r: int, c: int) -> bool:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return false
	return (_cells[r][c] as CellView).is_auto_mark_locked()


func get_puzzle_size() -> int:
	return _puzzle_size


func get_axis_auto_mark_btn(axis: int, idx: int) -> Control:
	var arr: Array = _row_auto_mark_btns if axis == 0 else _col_auto_mark_btns
	if idx < 0 or idx >= arr.size():
		return null
	return arr[idx] as Control


func get_axis_auto_mark_btn_global_rect(axis: int, idx: int) -> Rect2:
	var btn: Control = get_axis_auto_mark_btn(axis, idx)
	if btn == null:
		return Rect2()
	return btn.get_global_transform() * Rect2(Vector2.ZERO, btn.size)


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


func get_cell_state(r: int, c: int) -> int:
	if r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size or _cells.is_empty():
		return CellState.EMPTY
	return (_cells[r][c] as CellView).get_state()


func mark_cell_error(r: int, c: int, source: int = ChangeSource.USER_ACTION) -> void:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	var cur: int = (_cells[r][c] as CellView).get_state()

	if cur == CellState.LOCKED_MARK:
		return
	(_cells[r][c] as CellView).change_state({"state": CellState.ERROR, "play_anim": false})
	if cur != CellState.ERROR:
		cell_state_changed.emit(r, c, CellState.ERROR, source)


func play_error_feedback(r: int, c: int, source: int = ChangeSource.USER_ACTION) -> void:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return
	var cur: int = (_cells[r][c] as CellView).get_state()
	if cur == CellState.LOCKED_MARK:
		return
	(_cells[r][c] as CellView).change_state({"state": CellState.ERROR})
	if cur != CellState.ERROR:
		cell_state_changed.emit(r, c, CellState.ERROR, source)


func replay_all_cat_appear() -> void:
	if _cells.is_empty():
		return
	SoundManager.play(SoundManager.Kind.ALL_CLEARED)
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.force_play_appear(Vector2i(r, c) == _last_cat_cell)


func play_cat_cry_loop_all() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_cry_loop()


func play_cat_frustrated_all() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.play_frustrated_once()


func play_cat_frustrated_at(cells: Array) -> void:
	if _cells.is_empty():
		return
	for p: Vector2i in cells:
		var cell := get_cell_view(p.x, p.y)
		if cell != null and cell.get_state() == CellState.CAT:
			cell.play_frustrated_once()


func revive_all_cat_to_idle() -> void:
	if _cells.is_empty():
		return
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			var cell := _cells[r][c] as CellView
			if cell.get_state() == CellState.CAT:
				cell.revive_to_idle()


func get_board() -> Array:
	var board: Array = []
	for r in range(_puzzle_size):
		var row: Array[int] = []
		row.resize(_puzzle_size)
		for c in range(_puzzle_size):
			row[c] = (_cells[r][c] as CellView).get_state()
		board.append(row)
	return board


func get_cell_state_folded_board() -> Array:
	var board: Array = []
	for r in range(_puzzle_size):
		var row: Array[int] = []
		row.resize(_puzzle_size)
		for c in range(_puzzle_size):
			var s: int = (_cells[r][c] as CellView).get_state()
			if CellState.is_draft(s):
				row[c] = CellState.EMPTY
			elif s == CellState.ERROR or s == CellState.LOCKED_MARK:
				row[c] = CellState.MARK
			else:
				row[c] = s
		board.append(row)
	return board


func is_cell_error(r: int, c: int) -> bool:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return false
	return (_cells[r][c] as CellView).get_state() == CellState.ERROR


func count_error_cells() -> int:
	return _count_cells_in_state(CellState.ERROR)


func count_mark_cells() -> int:
	return _count_cells_in_state(CellState.MARK) + _count_cells_in_state(CellState.LOCKED_MARK)


func count_empty_cells() -> int:
	if _cells.is_empty():
		return 0
	var n: int = 0
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if CellState.is_blank((_cells[r][c] as CellView).get_state()):
				n += 1
	return n


func count_cat_cells() -> int:
	return _count_cells_in_state(CellState.CAT)


func _count_cells_in_state(state: int) -> int:
	if _cells.is_empty():
		return 0
	var n: int = 0
	for r in range(_puzzle_size):
		for c in range(_puzzle_size):
			if (_cells[r][c] as CellView).get_state() == state:
				n += 1
	return n


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


func get_cell_view(r: int, c: int) -> CellView:
	if _cells.is_empty() or r < 0 or r >= _puzzle_size or c < 0 or c >= _puzzle_size:
		return null
	return _cells[r][c] as CellView


func pointer_to_cell(px: float, py: float) -> Vector2i:
	if _puzzle_size == 0:
		return Vector2i(-1, -1)
	var col: int = int((px - BOARD_PADDING) / SLOT_PX)
	var row: int = int((py - BOARD_PADDING) / SLOT_PX)
	if row < 0 or row >= _puzzle_size or col < 0 or col >= _puzzle_size:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func update_swipe_protection_zone(lock: Dictionary) -> void:
	if _zone_viz != null and is_instance_valid(_zone_viz):
		_zone_viz.set_zone(lock)


func toggle_swipe_zone_viz() -> bool:
	_swipe_viz_on = not _swipe_viz_on
	if _zone_viz != null and is_instance_valid(_zone_viz):
		_zone_viz.set_enabled(_swipe_viz_on)
	return _swipe_viz_on


func _ensure_zone_viz() -> void:
	if _zone_viz == null or not is_instance_valid(_zone_viz) or not _zone_viz.is_inside_tree():
		_zone_viz = SwipeZoneDebugOverlay.new()
		_zone_viz.name = "SwipeZoneViz"
		add_child(_zone_viz)
	_zone_viz.configure(SLOT_PX, BOARD_PADDING, _puzzle_size)
	_zone_viz.set_enabled(_swipe_viz_on)


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


func clear_hint_cells() -> void:
	for cell in _hint_unit_cells:
		(_cells[cell.x][cell.y] as CellView).play_hide_hint()
	_hint_unit_cells = []
	_hint_key_cell = Vector2i(-1, -1)
	queue_redraw()


func get_region_color_index(region_idx: int) -> int:
	if region_idx < _color_map.size():
		return _color_map[region_idx] % _region_colors.size()
	return region_idx % _region_colors.size()


func get_region_color(region_idx: int) -> Color:
	var ci: int = get_region_color_index(region_idx)
	if ci < _region_colors.size():
		return _region_colors[ci]
	return Color.WHITE


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


func play_r2_preview_cell(r: int, c: int) -> void:
	if r >= 0 and r < _cells.size() and c >= 0 and c < (_cells[r] as Array).size():
		(_cells[r][c] as CellView).play_r2_preview()


func play_r2_preview_cell_delayed(r: int, c: int, delay: float) -> void:
	if r >= 0 and r < _cells.size() and c >= 0 and c < (_cells[r] as Array).size():
		(_cells[r][c] as CellView).play_r2_preview(delay)


func toggle_coords() -> void:
	_coord_visible = not _coord_visible
	GameState.coords_visible = _coord_visible
	for lbl in _coord_labels:
		lbl.visible = _coord_visible


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
		lbl.text = str(c + 1)
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
		lbl.text = str(r + 1)
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.85))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(44, SLOT_PX)
		lbl.position = Vector2(ox - 48, oy + r * SLOT_PX)
		lbl.visible = _coord_visible
		add_child(lbl)
		_coord_labels.append(lbl)


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
		if ABTestManager == null or ABTestManager.game_auto_mark == null or GameState == null:
			return
		if not ABTestManager.game_auto_mark.is_dot_toggle_enabled_at(GameState.get_current_level()):
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

	apply_inverse_scale_to_auto_mark_btns()


func apply_compensated_cell_corner_radius() -> void:
	if scale.x <= 0.0:
		return
	if _cells.is_empty():
		return
	for row in _cells:
		for cell in row:
			if cell is CellView:
				(cell as CellView).set_corner_radius_compensated(scale.x)


func apply_inverse_scale_to_auto_mark_btns() -> void:
	if scale.x <= 0.0:
		return
	if _puzzle_size == 0:
		return
	var inv: float = 1.0 / scale.x
	var inv_scale: Vector2 = Vector2(inv, inv)

	var preview_offset_x: float = 0.0
	var preview_offset_y: float = 0.0
	if Engine.is_editor_hint():
		var intrinsic: Vector2 = intrinsic_size_for(_puzzle_size)
		preview_offset_x = maxf(0.0, (size.x - intrinsic.x) * 0.5)
		preview_offset_y = maxf(0.0, (size.y - intrinsic.y) * 0.5)
	var ox: int = BOARD_PADDING
	var oy: int = BOARD_PADDING

	var col_y_dist_local: float = (_AUTO_MARK_BTN_OUT_GAP + _AUTO_MARK_BTN_H * 0.5) * inv
	var row_x_dist_local: float = (_AUTO_MARK_BTN_OUT_GAP + _AUTO_MARK_BTN_H * 0.5 + 2.0) * inv

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


func _apply_editor_btn_default_visual(btn: Node, is_editor: bool) -> void:
	if not is_editor:
		return
	var sprite_mark: Node = btn.get_node_or_null("BtnAutoMark")
	var sprite_unmark: Node = btn.get_node_or_null("BtnAutoUnMark")
	if sprite_mark != null:
		sprite_mark.visible = true
	if sprite_unmark != null:
		sprite_unmark.visible = false


func refresh_axis_auto_mark_state(axis: int, idx: int, is_marked: bool) -> void:
	var arr: Array = _row_auto_mark_btns if axis == 0 else _col_auto_mark_btns
	if idx < 0 or idx >= arr.size():
		return
	var btn = arr[idx]
	if not is_instance_valid(btn):
		return
	btn.set_marked(is_marked)


func is_axis_auto_mark_marked(axis: int, idx: int) -> bool:
	var arr: Array = _row_auto_mark_btns if axis == 0 else _col_auto_mark_btns
	if idx < 0 or idx >= arr.size():
		return false
	var btn = arr[idx]
	if not is_instance_valid(btn):
		return false
	return btn.is_marked()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
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
				cell_drag_end.emit()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if not _dragging:
				return
			var local_pos: Vector2 = (make_input_local(mm) as InputEventMouseMotion).position
			cell_drag_over.emit(local_pos)


func _render_editor_preview() -> void:
	var levels: Array = BankData.get_levels(9, 1)
	if levels.is_empty():
		push_warning("BoardView: editor_preview 未取到 9x9 题库(bankData9x9.json rank 1)")
		return
	var entry: Dictionary = levels[0]
	var raw_regions: Array = entry.get("regionMap", [])
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
				BOARD_PADDING + c * SLOT_PX + CELL_GAP + offset_x,
				BOARD_PADDING + r * SLOT_PX + CELL_GAP + offset_y,
			)

	if preview_auto_mark_btns:
		_rebuild_auto_mark_btns()
	queue_redraw()


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
