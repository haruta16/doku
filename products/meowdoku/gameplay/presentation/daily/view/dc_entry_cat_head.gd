## 每日挑战猫头像适配：应用装扮与明暗状态，按画面墨迹范围定位 Spine。
class_name DcEntryCatHead
extends RefCounted

const INK_SIZE: Vector2 = Vector2(253.0, 224.5)

const INK_CENTROID: Vector2 = Vector2(1.59, -111.66)

const _META_COSTUME_ID: StringName = &"_dc_entry_cat_head_costume_id"

const DIM_ALPHA: float = 0.5

const _IDLE_ANIM: String = "idle"


static func apply(spine: SpineSprite, costume_id: int, dimmed: bool) -> void:
	if spine == null or not is_instance_valid(spine):
		return
	spine.modulate.a = DIM_ALPHA if dimmed else 1.0

	if not spine.is_visible_in_tree():
		return
	if int(spine.get_meta(_META_COSTUME_ID, 0)) == costume_id:
		return
	CostumeSkin.apply(spine, costume_id)
	_freeze_idle(spine)
	spine.set_meta(_META_COSTUME_ID, costume_id)


static func place(spine: SpineSprite, design_centroid: Vector2, ink_width: float) -> void:
	if spine == null or not is_instance_valid(spine) or ink_width <= 0.0:
		return
	var scale_factor: float = ink_width / INK_SIZE.x
	spine.scale = Vector2(scale_factor, scale_factor)
	spine.position = design_centroid - INK_CENTROID * scale_factor


static func _freeze_idle(spine: SpineSprite) -> void:
	var data: SpineSkeletonDataResource = spine.get_skeleton_data_res()
	if data == null or data.find_animation(_IDLE_ANIM) == null:
		return
	var state: SpineAnimationState = spine.get_animation_state()
	if state == null:
		return
	state.set_animation(_IDLE_ANIM, false, 0)
	state.set_time_scale(0.0)
