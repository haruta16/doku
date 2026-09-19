# 评星弹窗（新版 UI）：开场动画播到 30% 处才一次性点亮五星
class_name RateUsPageV2
extends RateUsPage

# 开场动画进度到 30% 时点亮五星
const _STAR_FILL_AT: float = 0.3


# 换用另一条动画 GenericPopupV2
func _get_anim_name() -> StringName:
	return &"GenericPopupV2"


# 打开：先清零星星，等动画走到 30% 再点亮
func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	_select_stars(0)
	_anim.play_section_with_markers(_get_anim_name(), &"", &"Mark")
	# 轮询等待：动画还在播且未到 30% 就一直等下一帧
	while _anim.is_playing() and _anim.current_animation_position < _STAR_FILL_AT:
		await get_tree().process_frame
	_select_stars(5)


# 埋点附加：新版星 UI 标识
func get_dlg_extra() -> Dictionary:
	return {"dlg_star_ui": "dlg_star_ui_1"}
