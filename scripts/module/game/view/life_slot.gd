# 单个生命槽：只负责一颗心的显隐与得失动画，总生命数由页面统一驱动
class_name LifeSlot
extends Control

# ---- 子节点引用与状态 ----
@onready var _anim: AnimationPlayer = $AnimationPlayer # 播放 Appear / RESET 的动画器
var _is_lost: bool = false # 是否已失去（防止重复播放丢失动画）


# 只标记为已失去，不播动画（进场时同步历史结果用）
func mark_lost() -> void:
	_is_lost = true


# 显示为存活：回到 RESET 末帧
func show_alive() -> void:
	_is_lost = false
	# RESET 的末帧就是存活态
	if _anim != null:
		_anim.play("RESET")
		_anim.seek(_anim.current_animation_length, true)


# 显示为已失去；animate = false 时直接跳到动画末帧
func show_lost(animate: bool) -> void:
	if _anim == null:
		return
	# 已经丢过且不需要动画，跳过
	if not animate and _is_lost:
		return
	_is_lost = true
	# 播放失去动画
	_anim.play("Appear")
	# 不播动画就跳到末帧定住
	if not animate:
		_anim.seek(_anim.current_animation_length, true)


# 复活特效：播放另一个动画器上的 Revive
func play_revive() -> void:
	var life_plus_anim := get_node_or_null("AnimLifePlus") as AnimationPlayer
	if life_plus_anim != null and life_plus_anim.has_animation("Revive"):
		life_plus_anim.play("Revive")
