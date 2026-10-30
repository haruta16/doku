## 服装选择格；创建 Spine 预览、呈现持有或试用剩余时间，并维护选中外观。

class_name CostumeCell
extends UIChildWindow

signal cell_pressed(id: int)

signal cell_pressed_down(id: int)

const _FILL_AMOUNT: StringName = &"fill_amount"

const _SILHOUETTE_MODULATE: Color = Color(0.13, 0.12, 0.13, 1.0)

const _DAY_SEC: int = 24 * 3600
const _MAX_DAYS: int = 99

@onready var _cat_slot: Control = $CatSlot
@onready var _cat_icon: TextureRect = $CatSlot/CatIcon
@onready var _cat_anchor: Node2D = $CatSlot/CatAnchor
@onready var _trial_badge: Control = $TrialBadge
@onready var _trial_text: Label = $TrialBadge/Text
@onready var _check: Control = $Check

@onready var _cat_icon_mat: ShaderMaterial = _cat_icon.material as ShaderMaterial

var _id: int = 0

var _held: bool = false
var _spine: SpineSprite = null


func setup(costume_id: int) -> void:
	_id = costume_id
	var tex: Texture2D = CostumeIcon.texture_for(costume_id)

	_cat_icon.visible = tex != null
	_cat_icon.texture = tex
	if tex != null:
		if _spine != null:
			_spine.visible = false
		return
	_ensure_spine()
	_spine.visible = true
	CostumeSkin.apply(_spine, costume_id)


func _ensure_spine() -> void:
	if _spine != null:
		return
	_spine = SpineSprite.new()
	_spine.skeleton_data_res = CostumeSkin.SKELETON_RES
	_cat_anchor.add_child(_spine)


func set_hold_state(held: bool, trial_remaining_sec: int) -> void:
	_held = held
	_apply_hold_look(held)
	var in_trial: bool = held and trial_remaining_sec > 0
	_trial_badge.visible = in_trial
	if in_trial:
		_trial_text.text = _hhmm(trial_remaining_sec)


func _apply_hold_look(held: bool) -> void:
	if _cat_icon.visible and _cat_icon_mat != null:
		_cat_slot.modulate = Color.WHITE
		_cat_icon_mat.set_shader_parameter(_FILL_AMOUNT, 0.0 if held else 1.0)
		return
	_cat_slot.modulate = Color.WHITE if held else _SILHOUETTE_MODULATE


func set_selected(selected: bool) -> void:
	_check.visible = selected


func get_id() -> int:
	return _id


func _hhmm(sec: int) -> String:
	var left: int = maxi(0, sec)
	if left > _MAX_DAYS * _DAY_SEC:
		return "%dd+" % _MAX_DAYS
	if left > _DAY_SEC:
		@warning_ignore("integer_division")
		var days: int = left / _DAY_SEC
		@warning_ignore("integer_division")
		var day_hours: int = (left % _DAY_SEC) / 3600
		return "%dd%dh" % [days, day_hours]
	@warning_ignore("integer_division")
	var minutes: int = (left + 59) / 60
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _on_click_down() -> void:
	cell_pressed_down.emit(_id)


func _on_click_pressed() -> void:
	if not _held:
		return
	cell_pressed.emit(_id)
