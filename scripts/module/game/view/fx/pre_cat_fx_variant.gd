## 预放猫特效接口：约定准备、预计时长和异步播放，具体表现由子类实现。
class_name PreCatFxVariant
extends Control


func nominal_duration_sec() -> float:
	return 1.5


func setup(_ctx: PreCatFxContext) -> void:
	pass


const ANIM_NODE_NAME: String = "Anim"
const ANIM_NAME: String = "Play"


func play() -> void:
	var anim: AnimationPlayer = get_node_or_null(ANIM_NODE_NAME) as AnimationPlayer
	if anim == null or not anim.has_animation(ANIM_NAME):
		await get_tree().process_frame
		return
	anim.play(ANIM_NAME)
	await anim.animation_finished
