## 预放猫波纹表现：接收统一特效上下文，在预计时长内播放对应动画。
extends PreCatFxVariant

const _FALLBACK_DURATION_SEC: float = 2.1667

var _ctx: PreCatFxContext = null


func nominal_duration_sec() -> float:
	return _animation_duration_sec()


func setup(ctx: PreCatFxContext) -> void:
	_ctx = ctx


func play() -> void:
	if _ctx == null or not _ctx.reveal_cat.is_valid():
		await get_tree().process_frame
		return
	_ctx.reveal_cat.call(false, false, "CatIconGreet")
	await get_tree().create_timer(_animation_duration_sec()).timeout


func _animation_duration_sec() -> float:
	var src: Node2D = _ctx.cat_icon_source if _ctx != null else null
	var spine: SpineSprite = src as SpineSprite
	if spine != null:
		var data: SpineSkeletonDataResource = spine.get_skeleton_data_res()
		if data != null:
			var anim: SpineAnimation = data.find_animation("greet")
			if anim != null:
				return anim.get_duration()
	return _FALLBACK_DURATION_SEC
