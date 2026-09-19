# 动画播放工具（全静态）：play 前先回 RESET 基线并推进到第 0 帧，避免首帧闪
# 当前仓库内没有调用方，属于预留工具；缺动画时直接 push_error，不静默失败
class_name AnimUtil
extends RefCounted

# 约定的基线动画名：各 AnimationPlayer 用它回到初始姿态
const RESET_ANIM: StringName = &"RESET"


# 播放动画；reset=true 时先播 RESET 打基线。player 为空或动画缺失都只报错返回
static func play(player: AnimationPlayer, anim: StringName, reset: bool = true) -> void:
	if player == null:
		push_error("[AnimUtil] play: player 为 null (anim=%s)" % anim) # 报错而不是静默跳过，编辑器里立刻能看到
		return
	if not player.has_animation(anim): # 动画不存在就不播，免得停在半路
		push_error("[AnimUtil] play: 动画 '%s' 不存在于 %s" % [anim, player.get_path()])
		return
	if reset: # 先回基线：解决上一个动画把节点留在中间状态导致的首帧闪
		if player.has_animation(RESET_ANIM): # 有 RESET 就播它
			player.play(RESET_ANIM) # 切到基线姿态
			player.advance(0.0) # 推进 0 秒，立刻结算第 0 帧
		else: # 缺 RESET 只警告，不阻断播放
			push_warning(
				"[AnimUtil] %s 缺少 RESET 动画(目标=%s),无法 reset 基线,可能首帧闪" % [player.get_path(), anim]
			)
	player.play(anim) # 播放目标动画
	player.advance(0.0) # 同样推进 0 秒，让第一帧就是新动画的姿态
