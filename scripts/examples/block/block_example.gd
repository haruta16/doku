## 独立 Block 交互示例。用 tools/run_block_example.py 启动，不挂载 Meowdoku Autoload。
extends Control

const Result = preload("res://scripts/framework/operation_result.gd")

const Session = preload("res://scripts/examples/block/block_example_session.gd")
const Board = preload("res://scripts/examples/block/block_example_board.gd")
const Piece = preload("res://scripts/examples/block/block_example_piece.gd")

var storage_directory: String = ""
var _session: RefCounted
var _board: Control
var _piece: Control
var _score_label: Label
var _stars_label: Label
var _piece_label: Label
var _status_label: Label
var _new_button: Button
var _reload_button: Button
var _collect_button: Button
var _last_result: Dictionary = {}


func _ready() -> void:
	if storage_directory.is_empty():
		storage_directory = str(ProjectSettings.get_setting("example/storage_directory", "user://block_example"))
	_build_ui()
	_reload()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("142331")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := _label("BLOCK · 放块消行", 28, Color("e9f7f4"))
	column.add_child(title)
	column.add_child(_label("拖动下面的方块，或点击棋盘放置。填满一行或一列即可消除。", 16, Color("b6c7d8")))
	var counters := HBoxContainer.new()
	_score_label = _label("得分 0", 23, Color("a1efda"))
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stars_label = _label("星星 0", 20, Color("f6cf79"))
	counters.add_child(_score_label)
	counters.add_child(_stars_label)
	column.add_child(counters)
	var board_space := AspectRatioContainer.new()
	board_space.ratio = 1.0
	board_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board = Board.new()
	_board.name = "Board"
	_board.place_requested.connect(_place)
	board_space.add_child(_board)
	column.add_child(board_space)
	var tray := HBoxContainer.new()
	tray.custom_minimum_size.y = 110
	_piece = Piece.new()
	_piece.custom_minimum_size = Vector2(130, 104)
	tray.add_child(_piece)
	_piece_label = _label("", 17, Color("c4d5e4"))
	_piece_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray.add_child(_piece_label)
	_collect_button = _button("领取 1 颗星", _collect)
	tray.add_child(_collect_button)
	column.add_child(tray)
	_status_label = _label("", 16, Color("c4d5e4"))
	_status_label.custom_minimum_size.y = 44
	column.add_child(_status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_new_button = _button("新一局", _new_round)
	_reload_button = _button("重新读取", _reload)
	for button: Button in [_new_button, _reload_button, _button("退出示例", func() -> void: get_tree().quit())]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	column.add_child(actions)
	column.add_child(_label("每步自动保存。退出后从同一存档目录继续，星星不会重复领取。", 14, Color("8fa6bc")))


func _reload() -> void:
	var next := Session.new()
	var result: Dictionary = next.open(storage_directory)
	if result.get("ok", false):
		_session = next
		_board.session = _session
		_refresh()
	_report(result, "已读取保存的棋盘。")


func _new_round() -> void:
	if _session == null:
		return
	_report(_session.new_round(), "新一局已保存。试试用第一块补满最上面一行。")


func _place(row: int, col: int) -> void:
	if _session == null:
		return
	var result: Dictionary = _session.place(row, col)
	var message: String = "已保存。"
	if result.get("ok", false):
		var lines: int = result.result.get("cleared_rows", []).size() + result.result.get("cleared_cols", []).size()
		if lines > 0:
			message = "消除了 %d 条线，棋盘已保存。" % lines
	_report(result, message)


func _collect() -> void:
	if _session != null:
		_report(_session.collect(), "星星已保存。重复领取不会增加第二份。")


func _report(result: Dictionary, success_message: String) -> void:
	_last_result = result.duplicate(true)
	if result.get("ok", false):
		_refresh()
		_status_label.text = success_message
		_status_label.modulate = Color.WHITE
	else:
		var error: String = Result.code(result)
		match error:
			"invalid_placement": _status_label.text = "这里放不下。请换一个空位。"
			"round_not_playable", "round_settled": _status_label.text = "本局已结束，可以领取星星或开始新一局。"
			"round_not_finished": _status_label.text = "先完成本局，再领取星星。"
			_: _status_label.text = "保存或读取失败，棋盘未推进。请重试；不要删除原存档。"
		_status_label.modulate = Color("ffb5b8")
		push_warning("[BlockExample] " + Result.describe(result))


func _refresh() -> void:
	var current: Dictionary = _session.current()
	var snapshot: Dictionary = current.snapshot
	_board.show_snapshot(snapshot)
	_score_label.text = "得分 %d" % int(snapshot.score)
	_stars_label.text = "星星 %d" % _session.stars()
	var ended: bool = snapshot.finished
	var paid: bool = current.status == "settled"
	var shape: Array = [] if ended else snapshot.pieces[snapshot.piece_index]
	_piece.show_shape(shape, not ended, current.round_id, current.next_sequence)
	_piece_label.text = "本局完成 · 已领取" if paid else ("本局完成 · 可以领取星星" if ended else "下一块  %d / %d\n绿色预览可放，红色预览不可放。" % [int(snapshot.piece_index) + 1, snapshot.pieces.size()])
	_collect_button.visible = ended
	_collect_button.disabled = paid
	_collect_button.text = "已领取" if paid else "领取 1 颗星"


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


static func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(100, 46)
	button.add_theme_font_size_override("font_size", 17)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("355269") if state == "hover" else Color("263e52")
		if state == "disabled":
			style.bg_color = Color("203141")
		style.set_corner_radius_all(9)
		style.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button
