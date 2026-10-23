## 预放猫出现表现：实现统一的准备、时长和播放接口，供特效导演调用。
extends PreCatFxVariant

const _TOTAL_SEC: float = 0.6

var _ctx: PreCatFxContext = null


func nominal_duration_sec() -> float:
	return _TOTAL_SEC


func setup(ctx: PreCatFxContext) -> void:
	_ctx = ctx


func play() -> void:
	if _ctx == null or not _ctx.reveal_cat.is_valid():
		await get_tree().process_frame
		return

	_ctx.reveal_cat.call(true, true)

	await get_tree().create_timer(_TOTAL_SEC).timeout
