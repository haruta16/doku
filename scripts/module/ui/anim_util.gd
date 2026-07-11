class_name AnimUtil
extends RefCounted

const RESET_ANIM: StringName = &"RESET"


static func play(player: AnimationPlayer, anim: StringName, reset: bool = true) -> void:
	if player == null:
		push_error("[AnimUtil] play: player 为 null (anim=%s)" % anim)
		return
	if not player.has_animation(anim):
		push_error("[AnimUtil] play: 动画 '%s' 不存在于 %s" % [anim, player.get_path()])
		return
	if reset:
		if player.has_animation(RESET_ANIM):
			player.play(RESET_ANIM)
			player.advance(0.0)
		else:
			push_warning(
				"[AnimUtil] %s 缺少 RESET 动画(目标=%s),无法 reset 基线,可能首帧闪" % [player.get_path(), anim]
			)
	player.play(anim)
	player.advance(0.0)
