extends CanvasLayer
class_name DraftOnboardingTooltip

signal hit_draft_btn
signal closed

@onready var _mask: ColorRect = $MaskRect
@onready var _fake_btn: Control = $FakeBtn
@onready var _control: Control = $Control
@onready var _bubble_panel: Panel = $Control/BubblePanel
@onready var _bubble_label: Label = $Control/BubblePanel/BubbleLabel
@onready var _arrow: TextureRect = $Control/Arrow
@onready var _anim: AnimationPlayer = $AnimationPlayer

const _ANIM_NAME: StringName = &"BubblePanel"

const _DISAPPEAR_MARKER: StringName = &"Disappear"

const _BLOCK_DURATION_SEC: float = 0.5

const _ARROW_TO_BTN_GAP: float = -3.0

const _BUBBLE_PAD_H: float = 45.0
const _BUBBLE_PAD_V: float = 20.0

const _ARROW_PANEL_OVERLAP: float = 1.0

var _draft_btn_rect: Rect2 = Rect2()
var _block_until_ms: int = 0
var _closing: bool = false


func _ready() -> void:
	_block_until_ms = Time.get_ticks_msec() + int(_BLOCK_DURATION_SEC * 1000)
	_mask.gui_input.connect(_on_mask_input)
	_bubble_panel.gui_input.connect(_on_mask_input)


func show_at(draft_btn_global_rect: Rect2) -> void:
	_draft_btn_rect = draft_btn_global_rect
	var btn_pos: Vector2 = draft_btn_global_rect.position
	var btn_size: Vector2 = draft_btn_global_rect.size

	if _fake_btn.size.x > 0.0 and _fake_btn.size.y > 0.0:
		_fake_btn.scale = btn_size / _fake_btn.size
	_fake_btn.position = btn_pos

	_layout_bubble()

	var arrow_bottom_center_local: Vector2 = (
		_arrow.position + Vector2(_arrow.size.x / 2.0, _arrow.size.y)
	)

	var arrow_bottom_center_global: Vector2 = Vector2(
		btn_pos.x + btn_size.x / 2.0,
		btn_pos.y - _ARROW_TO_BTN_GAP,
	)
	_control.position = arrow_bottom_center_global - arrow_bottom_center_local

	_anim.play_section_with_markers(_ANIM_NAME, &"", _DISAPPEAR_MARKER)


func _layout_bubble() -> void:
	var txt_size: Vector2 = _bubble_label.get_minimum_size()
	var panel_size: Vector2 = Vector2(
		txt_size.x + _BUBBLE_PAD_H * 2.0,
		txt_size.y + _BUBBLE_PAD_V * 2.0,
	)

	_bubble_panel.custom_minimum_size = Vector2.ZERO
	_bubble_panel.position = Vector2.ZERO
	_bubble_panel.size = panel_size

	_bubble_label.offset_left = _BUBBLE_PAD_H
	_bubble_label.offset_top = _BUBBLE_PAD_V
	_bubble_label.offset_right = -_BUBBLE_PAD_H
	_bubble_label.offset_bottom = -_BUBBLE_PAD_V
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_arrow.position.y = panel_size.y - _ARROW_PANEL_OVERLAP

	_control.size = Vector2(panel_size.x, _arrow.position.y + _arrow.size.y)
	if _control.size.x > 0.0 and _control.size.y > 0.0:
		var arrow_bottom_center_local: Vector2 = (
			_arrow.position + Vector2(_arrow.size.x / 2.0, _arrow.size.y)
		)
		_control.pivot_offset_ratio = arrow_bottom_center_local / _control.size


func _on_mask_input(event: InputEvent) -> void:
	if _closing:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if Time.get_ticks_msec() < _block_until_ms:
		return

	if _draft_btn_rect.has_point(mb.position):
		hit_draft_btn.emit()
	else:
		closed.emit()
	_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	GameState.mark_draft_onboarding_shown()

	_anim.play_section_with_markers(_ANIM_NAME, _DISAPPEAR_MARKER, &"")
	await _anim.animation_finished
	queue_free()
