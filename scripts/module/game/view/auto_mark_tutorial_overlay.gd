class_name AutoMarkTutorialOverlay
extends Control

const _Z_DELTA_MASK: int = 400
const _Z_DELTA_HOIST: int = 500
const _Z_DELTA_HAND: int = 600

const _POP_UP_TOAST_SCENE: PackedScene = preload("res://assets/prefab/pop_up_toast.tscn")

const _TOAST_Y_ABOVE_BOARD: float = 170.0

@onready var _mask: ColorRect = $Mask
@onready var _hand_hint: Control = $HandHint
@onready var _hand_spine: Node = $HandHint/ui_guide_hand

signal closed(hit_btn: bool)

var _hoisted: Array = []
var _is_closed: bool = false

var _btn_hit_rect: Rect2 = Rect2()

var _toast: PopUpToast = null


func _ready() -> void:
	pass


func setup(board_view: BoardView, col: int) -> void:
	if board_view == null:
		push_error("[AutoMarkTutorialOverlay] setup: board_view == null")
		return
	var sz: int = board_view.get_puzzle_size()
	if sz <= 0 or col < 0 or col >= sz:
		push_error("[AutoMarkTutorialOverlay] setup: invalid col=%d sz=%d" % [col, sz])
		return
	var base_z: int = _resolve_base_z()

	_mask.z_index = base_z + _Z_DELTA_MASK
	_mask.z_as_relative = false
	_hand_hint.z_index = base_z + _Z_DELTA_HAND
	_hand_hint.z_as_relative = false

	for r in range(sz):
		var cell: CellView = board_view.get_cell_view(r, col)
		if cell != null:
			_hoist(cell, base_z)

	var btn: Control = board_view.get_axis_auto_mark_btn(1, col)
	if btn != null:
		_hoist(btn, base_z)

	var btn_rect: Rect2 = board_view.get_axis_auto_mark_btn_global_rect(1, col)
	if btn_rect.size != Vector2.ZERO:
		_btn_hit_rect = btn_rect
		var hx: float = btn_rect.get_center().x - _hand_hint.size.x * 0.5 + 65
		var hy: float = btn_rect.position.y - _hand_hint.size.y + 40.0 + 102
		_hand_hint.global_position = Vector2(hx, hy)

	if _hand_spine != null and _hand_spine.has_method("get_animation_state"):
		_hand_spine.get_animation_state().set_animation("click", true, 0)

	_spawn_toast(board_view, base_z)


func _resolve_base_z() -> int:
	var p: Node = get_parent()
	if p == null or not "z_index" in p:
		return 0
	return p.z_index


func _spawn_toast(board_view: BoardView, base_z: int) -> void:
	_toast = _POP_UP_TOAST_SCENE.instantiate() as PopUpToast
	add_child(_toast)

	_toast.anchor_left = 0.5
	_toast.anchor_top = 0.0
	_toast.anchor_right = 0.5
	_toast.anchor_bottom = 0.0
	_toast.offset_left = 0.0
	_toast.offset_right = 0.0
	_toast.offset_bottom = 0.0

	var board_top_y: float = board_view.global_position.y
	_toast.offset_top = board_top_y - _TOAST_Y_ABOVE_BOARD

	_toast.z_index = base_z + _Z_DELTA_HAND
	_toast.z_as_relative = false

	_toast.set_text(tr("AUTO_MARK_TUTORIAL"))
	_toast.pop_up()


func _hoist(node: CanvasItem, base_z: int) -> void:
	_hoisted.append({"node": node, "prev_z": node.z_index, "prev_rel": node.z_as_relative})
	node.z_as_relative = false
	node.z_index = base_z + _Z_DELTA_HOIST


func _restore_z() -> void:
	for entry in _hoisted:
		var node: CanvasItem = entry["node"] as CanvasItem
		if not is_instance_valid(node):
			continue
		node.z_index = entry["prev_z"]
		node.z_as_relative = entry["prev_rel"]
	_hoisted.clear()


func _input(event: InputEvent) -> void:
	if _is_closed:
		return
	var pressed: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not pressed:
		return

	var pos: Vector2 = (
		event.position
		if event is InputEventMouseButton
		else (event as InputEventScreenTouch).position
	)
	var hit_btn: bool = _btn_hit_rect.size != Vector2.ZERO and _btn_hit_rect.has_point(pos)
	_is_closed = true
	get_viewport().set_input_as_handled()
	_restore_z()

	_detach_and_dismiss_toast()
	closed.emit(hit_btn)


func _detach_and_dismiss_toast() -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	var new_parent: Node = get_parent()
	if new_parent != null and _toast.get_parent() == self:
		_toast.reparent(new_parent, true)

	if not _toast.dismissed.is_connected(_toast.queue_free):
		_toast.dismissed.connect(_toast.queue_free)
	_toast.dismiss()
	_toast = null


func _exit_tree() -> void:
	_restore_z()
