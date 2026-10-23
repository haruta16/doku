## 每日装扮引导页：聚焦目标猫并延迟启用关闭操作，避免入场触摸误跳过。
class_name DcCostumeTutorialPage
extends UIFrameWindow

signal tutorial_closed

const _ARM_DELAY_SEC: float = 0.3

const _IDLE_ANIM: StringName = &"idle"

const _BUBBLE_TOP_GAP: float = 33.0

const _TAIL_HEIGHT: float = 25.2

const _BUBBLE_HEIGHT: float = 115.0

const _BUBBLE_TOP_FALLBACK: float = 396.0

const _CAT_DESIGN_CENTROID: Vector2 = Vector2(40.59, 42.38)
const _CAT_INK_WIDTH: float = 72.05

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _spotlight: Control = $Spotlight
@onready var _tail: Sprite2D = $Content/Tail
@onready var _bubble: Control = $Content/Bubble
@onready var _cat_spine: SpineSprite = $Content/Bubble/SkinCat/CatSpine

var _closing: bool = false

var _armed: bool = false

var _arm_timer: Timer = null


func on_show(params: Dictionary = {}) -> void:
	_closing = false
	_armed = false
	_apply_costume(_resolve_costume_id(params))
	_build_spotlight(params.get("spotlight") as Control)
	if _arm_timer != null and is_instance_valid(_arm_timer):
		remove_timer(_arm_timer)
	_arm_timer = create_countdown(_ARM_DELAY_SEC, _on_armed)


func on_hide() -> void:
	_closing = true
	if _anim != null and _anim.has_animation(&"GenericPopup"):
		_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
		await _anim.animation_finished

	_clear_spotlight()
	tutorial_closed.emit()


func _input(event: InputEvent) -> void:
	if not is_showing() or _closing or not _armed:
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if not is_press:
		return
	get_viewport().set_input_as_handled()
	_close()


func on_escape() -> bool:
	if _armed and not _closing:
		_close()
	return true


func _on_armed() -> void:
	_armed = true


func _close() -> void:
	if _closing:
		return
	_closing = true
	UIManager.hide_ui(get_ui_name())


func _resolve_costume_id(params: Dictionary) -> int:
	var wanted: int = int(params.get("costume_id", 0))
	if CostumeCatalog.is_valid(wanted):
		return wanted
	return ProfileService.get_today_costume()


func _apply_costume(costume_id: int) -> void:
	if _cat_spine == null:
		return
	if _cat_spine.skeleton_data_res == null:
		_cat_spine.skeleton_data_res = CostumeSkin.SKELETON_RES

	DcEntryCatHead.place(_cat_spine, _CAT_DESIGN_CENTROID, _CAT_INK_WIDTH)
	_cat_spine.visible = true
	CostumeSkin.apply(_cat_spine, costume_id)
	var state := _cat_spine.get_animation_state()
	if state != null and _has_idle_clip():
		state.set_animation(_IDLE_ANIM, false, 0)
		state.set_time_scale(0.0)


func _has_idle_clip() -> bool:
	var data: SpineSkeletonDataResource = _cat_spine.get_skeleton_data_res()
	if data == null:
		return false
	return data.find_animation(_IDLE_ANIM) != null


func _build_spotlight(src: Control) -> void:
	_clear_spotlight()
	var usable: bool = src != null and is_instance_valid(src) and src.is_visible_in_tree()
	_tail.visible = usable
	if not usable:
		_place_bubble(_BUBBLE_TOP_FALLBACK)
		return
	var rect: Rect2 = src.get_global_rect()

	var copy: Node = src.duplicate(0)
	_strip_animators(copy)
	_spotlight.add_child(copy)
	var copy_ctrl: Control = copy as Control
	if copy_ctrl != null:
		copy_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		copy_ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		copy_ctrl.global_position = rect.position
		copy_ctrl.size = rect.size
	_place_bubble(rect.position.y + rect.size.y + _BUBBLE_TOP_GAP)
	_place_tail_x(rect.position.x + rect.size.x * 0.5)


func _strip_animators(node: Node) -> void:
	for child in node.get_children():
		if child is AnimationPlayer or child is CPUParticles2D or child is GPUParticles2D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_animators(child)


func _clear_spotlight() -> void:
	if _spotlight == null:
		return
	for child in _spotlight.get_children():
		_spotlight.remove_child(child)
		child.queue_free()


func _place_bubble(bubble_top: float) -> void:
	_bubble.offset_top = bubble_top
	_bubble.offset_bottom = bubble_top + _BUBBLE_HEIGHT
	if _tail.visible:
		_tail.position.y = bubble_top - _TAIL_HEIGHT * 0.5


func _place_tail_x(center_x: float) -> void:
	_tail.position.x = center_x
