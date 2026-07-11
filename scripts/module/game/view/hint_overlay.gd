class_name HintOverlay
extends CanvasLayer

const SPACING_TO_BOARD: float = 15.0

@onready var _overlay: ColorRect = $Overlay
@onready var _banner: Panel = $Banner
@onready var _btn_group: VBoxContainer = $BtnGroup
@onready var _strategy_label: Label = $Banner/StrategyLabel
@onready var _desc_label: RichTextLabel = $Banner/DescLabel
@onready var _detail_btn: Button = $Banner/DetailBtn
@onready var _dismiss_btn: Control = $BtnGroup/DismissBtn
@onready var _apply_btn: Control = $BtnGroup/ApplyBtn
@onready var _cancel_btn: Control = $BtnGroup/CancelBtn
@onready var _next_btn: Control = $BtnGroup/NextBtn
@onready var _close_btn: TextureButton = $Banner/CloseBtn

signal hint_applied
signal hint_dismissed
signal hint_detail_requested

var _hint: Dictionary = {}

var _next_step_revealed: bool = false


func _ready() -> void:
	UIHelper.bind_press_release_scale(_detail_btn)


func show_hint(hint: Dictionary) -> void:
	_hint = hint
	var strategy: String = hint.get("strategy", "")
	match strategy:
		"R1_mark":
			_strategy_label.text = "R1"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_R1_MARK")))
		"R2":
			_strategy_label.text = "R2"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_REGION_CONSTRAINT")))
		"R3":
			_strategy_label.text = "R3"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_SET_LOCKING")))
		"R4":
			_strategy_label.text = "R4"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_LARGE_SET_LOCKING")))
		"R4_chain":
			_strategy_label.text = "R4"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_CONTRADICTION")))
		"R5_chain":
			_strategy_label.text = "R5"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_CONTRADICTION")))
		_:
			_strategy_label.text = "R1"
			var unit_type: String = hint.get("unit_type", "")
			var desc_override: String = hint.get("description", "")
			if desc_override != "":
				_desc_label.clear()
				_desc_label.append_text(desc_override)
			elif unit_type == "full_line":
				_desc_label.clear()
				_desc_label.append_text(tr("HINT_INTERSECTION"))
			else:
				var unit_name: String
				match unit_type:
					"row":
						unit_name = tr("HINT_ROW") % (hint.get("unit_index", 0) + 1)
					"col":
						unit_name = tr("HINT_COL") % (hint.get("unit_index", 0) + 1)
					"region":
						unit_name = tr("HINT_COLOR_REGION")
					_:
						unit_name = tr("HINT_UNIT_ROW_COL_REGION")
				_desc_label.clear()
				_desc_label.append_text(tr("HINT_ONLY_ONE_CELL") % unit_name)

	var _chain_d: Dictionary = hint.get("chain", {})
	var has_steps := (
		(strategy == "R4_chain" or strategy == "R5_chain")
		and not _chain_d.is_empty()
		and (_chain_d.get("steps", []) as Array).size() > 0
	)
	_next_step_revealed = false
	var _is_v1: bool = ABTestManager.hint_ue.is_new_hint_flow()
	var _is_v2: bool = ABTestManager.hint_ue.is_close_btn_flow()
	if _is_v1 or _is_v2:
		_detail_btn.visible = false
		_dismiss_btn.visible = false
		_cancel_btn.visible = false
		_close_btn.visible = false
		if has_steps:
			_apply_btn.visible = false
			_next_btn.visible = true
			_close_btn.visible = _is_v2
		else:
			_apply_btn.visible = true
			_next_btn.visible = false
			if _is_v2:
				_close_btn.visible = true
			else:
				_cancel_btn.visible = true
	else:
		_apply_btn.visible = true
		_detail_btn.visible = has_steps
		_dismiss_btn.visible = false
		_cancel_btn.visible = false
		_next_btn.visible = false
		_close_btn.visible = false

	var _debug: bool = GameState.is_debug_mode()
	_strategy_label.visible = _debug
	var _left: float = 210.0 if _debug else 50.0

	var _right: float = (_detail_btn.position.x - 20.0) if _detail_btn.visible else 850.0
	_desc_label.offset_left = _left
	_desc_label.offset_right = _right
	_desc_label.offset_top = 0.0
	_desc_label.offset_bottom = 190.0

	call_deferred("_center_desc_label")
	visible = true
	_overlay.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.75, 0.3)

	call_deferred("_align_to_board")


func _on_apply_btn_pressed() -> void:
	visible = false
	hint_applied.emit()


func _on_dismiss_btn_pressed() -> void:
	visible = false
	hint_dismissed.emit()


func _on_cancel_btn_pressed() -> void:
	visible = false
	hint_dismissed.emit()


func _on_close_btn_pressed() -> void:
	visible = false
	hint_dismissed.emit()


func _on_next_btn_pressed() -> void:
	_next_step_revealed = true
	_next_btn.visible = false
	_apply_btn.visible = true
	if ABTestManager.hint_ue.is_close_btn_flow():
		_close_btn.visible = true
	else:
		_cancel_btn.visible = true

	hint_detail_requested.emit()

	call_deferred("_align_to_board")


func _on_detail_btn_pressed() -> void:
	_detail_btn.visible = false
	_desc_label.offset_right = 850.0
	hint_detail_requested.emit()


func _center_desc_label() -> void:
	var content_h: float = _desc_label.get_content_height()
	var total_h: float = 190.0
	var top: float = maxf(0.0, (total_h - content_h) / 2.0)
	_desc_label.offset_top = top
	_desc_label.offset_bottom = top + content_h


func update_desc(text: String) -> void:
	_desc_label.clear()
	_desc_label.append_text(text)


func show_dismiss_btn() -> void:
	if ABTestManager.hint_ue.is_any_new_flow():
		pass
	else:
		_dismiss_btn.visible = true


func _align_to_board() -> void:
	var board := _find_board()
	if board == null:
		return
	var board_top: float = board.global_position.y
	var board_bottom: float = board_top + board.size.y * board.scale.y
	var viewport_h: float = get_viewport().get_visible_rect().size.y

	var banner_h: float = _banner.size.y
	_banner.offset_bottom = board_top - SPACING_TO_BOARD
	_banner.offset_top = _banner.offset_bottom - banner_h

	var btn_h: float = _btn_group.size.y
	_btn_group.offset_top = (board_bottom + SPACING_TO_BOARD) - viewport_h
	_btn_group.offset_bottom = _btn_group.offset_top + btn_h


func _find_board() -> Control:
	var page_root := get_parent()
	if page_root == null:
		return null
	return page_root.get_node_or_null("VBoxContainer/BoardContainer/BoardView") as Control
