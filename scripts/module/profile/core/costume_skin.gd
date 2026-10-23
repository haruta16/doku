## 将服装编号映射为 Spine 皮肤并应用到骨骼实例；把角色外观资源的细节集中在一处。

class_name CostumeSkin
extends RefCounted

const SKELETON_RES: SpineSkeletonDataResource = preload(
	"res://assets/effect/spine/ui_cat_icon/ui_cat_icon.tres"
)


## 解析服装对应的皮肤并应用到 Spine 骨骼，再恢复插槽初始姿态并更新骨骼；无有效实例时直接返回。
static func apply(spine: SpineSprite, costume_id: int) -> void:
	if spine == null or not is_instance_valid(spine):
		return
	var skeleton: SpineSkeleton = spine.get_skeleton()
	if skeleton == null:
		return
	var data: SpineSkeletonDataResource = spine.get_skeleton_data_res()
	if data == null:
		return

	var skin: SpineSkin = resolve_skin(data, CostumeCatalog.skin_for(costume_id))
	skeleton.set_skin(skin)

	skeleton.set_slots_to_setup_pose()

	spine.update_skeleton(0.0)


static func resolve_skin(data: SpineSkeletonDataResource, skin_name: String) -> SpineSkin:
	if data == null or skin_name.is_empty():
		return null
	return data.find_skin(skin_name)
