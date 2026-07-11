class_name HowToPlayPage
extends UIFrameWindow

signal closed

const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")

const _ROWS: int = 3
const _COLS: int = 5
const _CELL_PX: float = 100.0
const _RENDER_SLOT: float = 140.0
const _CELL_RAD: int = 7
const _BOARD_SCALE: float = 1.33

const _CARD_W: float = 717.0
const _CARD_H: float = 434.0
const _CARD_X: float = 181.0
const _CARD_TOP: Array = [403.0, 1021.0, 1640.0]
const _BOARD_MARGIN_Y: float = 12.0
const _TITLE_CENTER_DY: float = -70.0

const _DIVIDER_TOP: Array = [863.0, 1488.0]
const _DIVIDER_X: float = 59.0
const _DIVIDER_W: float = 969.0
const _DIVIDER_H: float = 16.0

const _PAL_BLUE: int = 8
const _PAL_PINK: int = 1
const _PAL_YELLOW: int = 5
var _palette: PackedColorArray = PackedColorArray()

const _FPS: float = 60.0
const _CROSS_STEP_FRAMES: int = 5
const _START_DELAY_FRAMES: int = 6
const _GAP_FRAMES: int = 12
const _GAP_LAST_FRAMES: int = 24

const _CROSS_ANIM: String = "CrossOutAppear_2"
const _ERROR_ANIM: String = "ErrorAppear_2"
const _DISAPPEAR_ANIM: String = "DemoDisappear"

const _LEN_CROSS: float = 0.35
const _LEN_ERROR: float = 1.1

var _DEMOS: Array = [
	{
		"colors": ["BBBBP", "BBBPY", "BBPYP"],
		"cat_appear": [Vector2i(0, 1)],
		"cat_static": [Vector2i(2, 3)],
		"cross_static": [Vector2i(1, 4)],
		"error": {"frame": 72, "cell": Vector2i(2, 1)},
		"cross_waves":
		[
			{"frame": 134, "cells": [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 3)]},
			{"frame": 158, "cells": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)]},
			{"frame": 182, "cells": [Vector2i(2, 0)]},
		],
	},
	{
		"colors": ["PYPYP", "BBBBB", "PYPYP"],
		"cat_appear": [Vector2i(1, 2)],
		"cat_static": [],
		"cross_static": [],
		"error": {},
		"cross_waves":
		[
			{"frame": 72, "cells": [Vector2i(0, 2), Vector2i(2, 2)]},
			{
				"frame": 92,
				"cells": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 4)]
			},
		],
	},
	{
		"colors": ["PPBBY", "PBBBP", "YBBPP"],
		"cat_appear": [Vector2i(1, 2)],
		"cat_static": [],
		"cross_static": [],
		"error": {},
		"cross_waves":
		[
			{
				"frame": 72,
				"cells":
				[
					Vector2i(2, 1),
					Vector2i(1, 1),
					Vector2i(0, 1),
					Vector2i(0, 2),
					Vector2i(0, 3),
					Vector2i(1, 3),
					Vector2i(2, 3),
					Vector2i(2, 2),
				]
			},
		],
	},
]

@onready var _holders: Array = [$Root/Content/Board1, $Root/Content/Board2, $Root/Content/Board3]
@onready var _cards: Array = [$Root/Content/Card1, $Root/Content/Card2, $Root/Content/Card3]
@onready var _titles: Array = [$Root/Content/Title1, $Root/Content/Title2, $Root/Content/Title3]
@onready var _dividers: Array = [$Root/Content/Divider1, $Root/Content/Divider2]
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _cells: Array = []
var _built: bool = false

var _demo_token: int = 0


func _ready() -> void:
	_center_content()
	_layout()
	_build_boards()


func _center_content() -> void:
	var c := get_node_or_null("Root/Content") as Control
	if c == null:
		return
	c.anchor_left = 0.5
	c.anchor_top = 0.5
	c.anchor_right = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -540.0
	c.offset_top = -1200.0
	c.offset_right = 540.0
	c.offset_bottom = 1200.0


func _layout() -> void:
	var board_render_w: float = 4.0 * _RENDER_SLOT + _CELL_PX * _BOARD_SCALE
	for b in range(_CARD_TOP.size()):
		var top: float = _CARD_TOP[b]
		var card: Panel = _cards[b]
		card.position = Vector2(_CARD_X, top)
		card.size = Vector2(_CARD_W, _CARD_H)
		var title: Label = _titles[b]
		title.position = Vector2(0.0, top + _TITLE_CENTER_DY - 40.0)
		title.size = Vector2(1080.0, 80.0)
		var holder: Control = _holders[b]
		holder.scale = Vector2(_BOARD_SCALE, _BOARD_SCALE)
		holder.position = Vector2(_CARD_X + (_CARD_W - board_render_w) / 2.0, top + _BOARD_MARGIN_Y)

	for d in range(_DIVIDER_TOP.size()):
		var divider: NinePatchRect = _dividers[d]
		divider.position = Vector2(_DIVIDER_X, _DIVIDER_TOP[d])
		divider.size = Vector2(_DIVIDER_W, _DIVIDER_H)


func on_show(_params: Dictionary = {}) -> void:
	SoundManager.set_silent(true)

	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")
	_demo_token += 1
	_run_demo(_demo_token)


func on_hide() -> void:
	_stop_demo()


func _on_back_request() -> void:
	_close()


func _input(event: InputEvent) -> void:
	if not visible or not _is_topmost_visible_page():
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if is_press:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	UIManager.hide_ui(UiName.HOW_TO_PLAY)


func _is_topmost_visible_page() -> bool:
	if not is_inside_tree():
		return false
	var parent := get_parent()
	if parent == null:
		return true
	for sibling in parent.get_children():
		if sibling == self or not (sibling is UIFrameWindow):
			continue
		var s := sibling as Control
		if s.visible and s.z_index > z_index:
			return false
	return true


func _stop_demo() -> void:
	_demo_token += 1
	SoundManager.set_silent(false)


func _char_color(ch: String) -> Color:
	if _palette.is_empty():
		_palette = BoardView.resolve_region_palette()
	var idx: int = _PAL_BLUE
	match ch:
		"P":
			idx = _PAL_PINK
		"Y":
			idx = _PAL_YELLOW
	return _palette[idx] if idx < _palette.size() else Color(0.5, 0.5, 0.5)


func _build_boards() -> void:
	if _built:
		return
	_built = true
	var slot_unscaled: float = _RENDER_SLOT / _BOARD_SCALE
	for b in range(_DEMOS.size()):
		var holder: Control = _holders[b]
		var colors: Array = _DEMOS[b]["colors"]
		var board_cells: Array = []
		for r in range(_ROWS):
			var row_cells: Array = []
			for c in range(_COLS):
				var cell: CellView = _CELL_SCENE.instantiate() as CellView
				cell.position = Vector2(c * slot_unscaled, r * slot_unscaled)
				cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
				holder.add_child(cell)
				cell.set_region_color(_char_color((colors[r] as String)[c]))
				cell.set_corner_radius(_CELL_RAD)
				cell.change_state({"state": CellState.EMPTY, "play_anim": false})
				row_cells.append(cell)
			board_cells.append(row_cells)
		_cells.append(board_cells)


func _run_demo(token: int) -> void:
	_reset_all()

	for i in range(1, _DEMOS.size()):
		_fill_demo_complete(i)
	if not await _wait_frames(_START_DELAY_FRAMES, token):
		return
	if not await _play_demo(0, token):
		return
	var cur: int = 0
	while token == _demo_token and visible:
		var nxt: int = (cur + 1) % _DEMOS.size()
		var gap: int = _GAP_LAST_FRAMES if cur == _DEMOS.size() - 1 else _GAP_FRAMES
		if not await _wait_frames(gap, token):
			return
		if not await _clear_board(nxt, token):
			return
		if not await _play_demo(nxt, token):
			return
		cur = nxt


func _play_demo(idx: int, token: int) -> bool:
	var demo: Dictionary = _DEMOS[idx]

	for c: Vector2i in demo["cat_appear"]:
		_cell(idx, c).demo_cat(true)
	for c: Vector2i in demo["cat_static"]:
		_cell(idx, c).demo_cat(false)
	for c: Vector2i in demo["cross_static"]:
		_cell(idx, c).demo_play(_CROSS_ANIM, true)

	var events: Array = []
	var err: Dictionary = demo["error"]
	if not err.is_empty():
		events.append({"frame": int(err["frame"]), "cell": err["cell"], "anim": _ERROR_ANIM})
	for wave: Dictionary in demo["cross_waves"]:
		var base: int = int(wave["frame"])
		var cells: Array = wave["cells"]
		for k in range(cells.size()):
			events.append(
				{"frame": base + k * _CROSS_STEP_FRAMES, "cell": cells[k], "anim": _CROSS_ANIM}
			)
	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["frame"]) < int(b["frame"])
	)

	var last_frame: int = 0
	var demo_end_sec: float = 0.0
	for e: Dictionary in events:
		var f: int = int(e["frame"])
		var dt: float = float(f - last_frame) / _FPS
		if dt > 0.0 and not await _wait(dt, token):
			return false
		last_frame = f
		_cell(idx, e["cell"]).demo_play(e["anim"])
		demo_end_sec = maxf(demo_end_sec, float(f) / _FPS + _anim_len(e["anim"]))
	var tail: float = demo_end_sec - float(last_frame) / _FPS
	if tail > 0.0 and not await _wait(tail, token):
		return false
	return true


func _clear_board(idx: int, token: int) -> bool:
	var cells: Array = _clearable_cells(idx)
	if cells.is_empty():
		return true
	for c: Vector2i in cells:
		_cell(idx, c).demo_play(_DISAPPEAR_ANIM)
	if not await _wait(_anim_len(_DISAPPEAR_ANIM), token):
		return false
	for c: Vector2i in cells:
		_cell(idx, c).demo_clear()
	return true


func _clearable_cells(idx: int) -> Array:
	var demo: Dictionary = _DEMOS[idx]
	var skip: Dictionary = {}
	for c: Vector2i in demo["cat_static"]:
		skip[c] = true
	for c: Vector2i in demo["cross_static"]:
		skip[c] = true
	var out: Array = []
	for c: Vector2i in _content_cells(idx):
		if not skip.has(c):
			out.append(c)
	return out


func _fill_demo_complete(idx: int) -> void:
	var demo: Dictionary = _DEMOS[idx]
	for c: Vector2i in demo["cat_appear"]:
		_cell(idx, c).demo_cat(false)
	for c: Vector2i in demo["cat_static"]:
		_cell(idx, c).demo_cat(false)
	for c: Vector2i in demo["cross_static"]:
		_cell(idx, c).demo_play(_CROSS_ANIM, true)
	var err: Dictionary = demo["error"]
	if not err.is_empty():
		_cell(idx, err["cell"]).demo_play(_ERROR_ANIM, true)
	for wave: Dictionary in demo["cross_waves"]:
		for c: Vector2i in wave["cells"]:
			_cell(idx, c).demo_play(_CROSS_ANIM, true)


func _reset_all() -> void:
	for b in range(_cells.size()):
		for r in range(_ROWS):
			for c in range(_COLS):
				(_cells[b][r][c] as CellView).demo_clear()


func _content_cells(idx: int) -> Array:
	var demo: Dictionary = _DEMOS[idx]
	var out: Array = []
	out.append_array(demo["cat_appear"])
	out.append_array(demo["cat_static"])
	out.append_array(demo["cross_static"])
	var err: Dictionary = demo["error"]
	if not err.is_empty():
		out.append(err["cell"])
	for wave: Dictionary in demo["cross_waves"]:
		out.append_array(wave["cells"])
	return out


func _cell(board: int, c: Vector2i) -> CellView:
	return _cells[board][c.x][c.y] as CellView


func _anim_len(anim_name: String) -> float:
	if not _cells.is_empty():
		var v: float = (_cells[0][0][0] as CellView).demo_anim_length(anim_name)
		if v > 0.0:
			return v
	return _LEN_ERROR if anim_name == _ERROR_ANIM else _LEN_CROSS


func _wait_frames(frames: int, token: int) -> bool:
	return await _wait(float(frames) / _FPS, token)


func _wait(sec: float, token: int) -> bool:
	await get_tree().create_timer(sec).timeout
	return token == _demo_token and visible
