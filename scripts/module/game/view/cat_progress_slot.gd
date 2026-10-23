## 猫咪进度槽：组合猫脸、装扮和错标图层，按槽位状态切换动画与布局。
class_name CatProgressSlot
extends Control

@onready var _color_base: TextureRect = $ColorBase
@onready var _silhouette: TextureRect = $Silhouette
@onready var _face: TextureRect = $Face
@onready var _color_face: TextureRect = $ColorFace

@onready var _costume_cat_icon: TextureRect = get_node_or_null("CostumeCat") as TextureRect

var _costume_cat_spine: SpineSprite = null

@onready var _dot_root: Control = get_node_or_null("CatDotRoot") as Control

@onready var _dot: TextureRect = get_node_or_null("CatDotRoot/CatDot") as TextureRect

var _was_revealed: bool = false

@onready var _wrong_mark: TextureRect = get_node_or_null("WrongMark") as TextureRect
var _wrong_mark_on: bool = false
var _face_pop_tween: Tween = null

var _done_dot_on: bool = false

const DESIGN_TINT: Color = Color(0.9490196, 0.89411765, 0.84313726, 1.0)

const COLORED_SILHOUETTE_ALPHA: float = 0.5

const COLORED_BASE_DESIGN_SIZE: Vector2 = Vector2(76.0, 77.0)
const COLORED_BASE_DESIGN_SLOT: float = 66.0

const COLORED_BASE_SCALE: float = 0.755

const COLORED_BASE_WIDTH_RATIO: float = (
	COLORED_BASE_DESIGN_SIZE.x / COLORED_BASE_DESIGN_SLOT * COLORED_BASE_SCALE
)

const COLORED_BASE_HEIGHT_RATIO: float = (
	COLORED_BASE_DESIGN_SIZE.y / COLORED_BASE_DESIGN_SLOT * COLORED_BASE_SCALE
)


func apply_state(revealed: bool, tint: Color, colored_mode: bool) -> void:
	if _silhouette != null:
		_silhouette.visible = (not revealed) and (not colored_mode)
		_silhouette.modulate = tint
	if _color_base != null:
		_color_base.visible = colored_mode and (not revealed)
		_color_base.modulate = tint

	if _dot_root != null:
		_dot_root.visible = revealed and _done_dot_on
		if _dot != null and _done_dot_on:
			_dot.modulate = tint

	_costume_last_colored = colored_mode
	_apply_cat_face_layers(revealed, colored_mode)
	if colored_mode:
		_layout_colored_layers()

	var newly_revealed: bool = revealed and not _was_revealed
	if newly_revealed:
		var tex: Texture2D = CostumeIcon.texture_for(_costume_id) if _costume_on else null
		if tex != null and _costume_cat_icon != null:
			_play_face_pop(_costume_cat_icon)
		elif _costume_on and _costume_cat_spine != null:
			_play_costume_spine_pop()
		else:
			_play_face_pop(_color_face if colored_mode else _face)
	elif not revealed:
		_reset_face_scale()
	_was_revealed = revealed
	_refresh_wrong_mark()


func set_wrong_mark(on: bool) -> void:
	_wrong_mark_on = on
	_refresh_wrong_mark()


func _refresh_wrong_mark() -> void:
	if _wrong_mark != null:
		_wrong_mark.visible = _wrong_mark_on and not _was_revealed


func set_done_dot_mode(on: bool) -> void:
	_done_dot_on = on
	if _dot_root != null:
		_dot_root.visible = _done_dot_on and _was_revealed


func _layout_colored_layers() -> void:
	var grow_x: float = (COLORED_BASE_WIDTH_RATIO - 1.0) * 0.5 * size.x
	var grow_y: float = (COLORED_BASE_HEIGHT_RATIO - 1.0) * 0.5 * size.y
	var layers: Array = [_color_base, _color_face]
	for layer: TextureRect in layers:
		if layer == null:
			continue
		layer.offset_left = -grow_x
		layer.offset_right = grow_x
		layer.offset_top = -grow_y
		layer.offset_bottom = grow_y


func _play_face_pop(target: TextureRect) -> void:
	if target == null:
		return
	if _face_pop_tween != null and _face_pop_tween.is_valid():
		_face_pop_tween.kill()

	target.scale = Vector2.ZERO
	_face_pop_tween = create_tween()
	(
		_face_pop_tween
		. tween_property(target, "scale", Vector2.ONE * FACE_POP_OVERSHOOT, FACE_POP_UP_SEC)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		_face_pop_tween
		. tween_property(target, "scale", Vector2.ONE, FACE_POP_DOWN_SEC)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)


func _reset_face_scale() -> void:
	if _face_pop_tween != null and _face_pop_tween.is_valid():
		_face_pop_tween.kill()
	if _face != null:
		_face.scale = Vector2.ONE
	if _color_face != null:
		_color_face.scale = Vector2.ONE
	if _costume_cat_icon != null:
		_costume_cat_icon.scale = Vector2.ONE
	if _costume_pop_tween != null and _costume_pop_tween.is_valid():
		_costume_pop_tween.kill()
	if _costume_cat_spine != null:
		_costume_cat_spine.scale = _costume_base_scale


const COSTUME_CAT_REF_BOX_PX: float = 100.0
const COSTUME_CAT_REF_SCALE: float = 0.35

const COSTUME_CAT_ORIGIN_Y_RATIO: float = 0.88

const COSTUME_IDLE_ANIM: String = "idle"

const FACE_POP_OVERSHOOT: float = 1.2
const FACE_POP_UP_SEC: float = 0.13
const FACE_POP_DOWN_SEC: float = 0.22

var _costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID

var _costume_on: bool = false

var _costume_applied_id: int = -1

var _costume_last_colored: bool = false

var _costume_base_scale: Vector2 = Vector2.ONE
var _costume_pop_tween: Tween = null


func set_cat_costume(costume_id: int, use_costume: bool) -> void:
	_costume_id = costume_id
	_costume_on = use_costume
	_apply_cat_face_layers(_was_revealed, _costume_last_colored)


func _apply_cat_face_layers(revealed: bool, colored_mode: bool) -> void:
	var tex: Texture2D = CostumeIcon.texture_for(_costume_id) if _costume_on else null

	var icon_takes_over: bool = tex != null and _costume_cat_icon != null
	var spine_takes_over: bool = _costume_on and tex == null
	var costume_takes_over: bool = icon_takes_over or spine_takes_over
	if _face != null:
		_face.visible = revealed and (not colored_mode) and (not costume_takes_over)
	if _color_face != null:
		_color_face.visible = colored_mode and revealed and (not costume_takes_over)
	if _costume_cat_icon != null:
		var show_icon: bool = icon_takes_over and revealed
		_costume_cat_icon.visible = show_icon
		if show_icon:
			_costume_cat_icon.texture = tex
	var show_spine: bool = spine_takes_over and revealed
	if not show_spine:
		if _costume_cat_spine != null:
			_costume_cat_spine.visible = false
		return
	_ensure_costume_spine()
	_costume_cat_spine.visible = true
	_layout_costume_spine()


func _ensure_costume_spine() -> void:
	if _costume_cat_spine == null:
		_costume_cat_spine = SpineSprite.new()
		add_child(_costume_cat_spine)
	if _costume_cat_spine.skeleton_data_res != CostumeSkin.SKELETON_RES:
		_costume_cat_spine.skeleton_data_res = CostumeSkin.SKELETON_RES

		_costume_applied_id = -1
	if _costume_applied_id == _costume_id:
		return

	if _costume_cat_spine.get_skeleton() == null:
		return
	CostumeSkin.apply(_costume_cat_spine, _costume_id)
	_freeze_costume_spine_idle()
	_costume_applied_id = _costume_id


func _layout_costume_spine() -> void:
	_costume_base_scale = Vector2.ONE * (size.x / COSTUME_CAT_REF_BOX_PX * COSTUME_CAT_REF_SCALE)
	_costume_cat_spine.position = Vector2(size.x * 0.5, size.y * COSTUME_CAT_ORIGIN_Y_RATIO)

	if _costume_pop_tween == null or not _costume_pop_tween.is_running():
		_costume_cat_spine.scale = _costume_base_scale


func _freeze_costume_spine_idle() -> void:
	var data: SpineSkeletonDataResource = _costume_cat_spine.get_skeleton_data_res()
	if data == null or data.find_animation(COSTUME_IDLE_ANIM) == null:
		return
	var state: SpineAnimationState = _costume_cat_spine.get_animation_state()
	if state == null:
		return
	state.set_animation(COSTUME_IDLE_ANIM, false, 0)
	state.set_time_scale(0.0)


func _play_costume_spine_pop() -> void:
	if _costume_cat_spine == null:
		return
	if _costume_pop_tween != null and _costume_pop_tween.is_valid():
		_costume_pop_tween.kill()
	_costume_cat_spine.scale = Vector2.ZERO
	_costume_pop_tween = create_tween()
	(
		_costume_pop_tween
		. tween_property(
			_costume_cat_spine, "scale", _costume_base_scale * FACE_POP_OVERSHOOT, FACE_POP_UP_SEC
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		_costume_pop_tween
		. tween_property(_costume_cat_spine, "scale", _costume_base_scale, FACE_POP_DOWN_SEC)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
