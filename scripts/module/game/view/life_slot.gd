## 单个生命槽：管理存活、失去、金色、复活和高亮的视觉状态。
class_name LifeSlot
extends Control

# ---- 子节点引用与状态 ----
@onready var _anim: AnimationPlayer = $AnimationPlayer # 播放 Appear / RESET 的动画器
var _is_lost: bool = false # 是否已失去（防止重复播放丢失动画）


## 只标记为已失去，不播动画（进场时同步历史结果用）
func mark_lost() -> void:
	_is_lost = true


## 显示为存活：回到 RESET 末帧
func show_alive() -> void:
	_is_lost = false
	# RESET 的末帧就是存活态
	if _anim != null:
		_anim.play("RESET")
		_anim.seek(_anim.current_animation_length, true)


func show_lost(animate: bool, silent: bool = false) -> void:
	if _anim == null:
		return
	if not animate and _is_lost:
		return
	_is_lost = true
	stop_highlight_glow()
	var anim_name: StringName = (
		&"Disappear" if silent and _anim.has_animation(&"Disappear") else &"Appear"
	)
	_anim.play(anim_name)
	if not animate:
		_anim.seek(_anim.current_animation_length, true)


const GOLDEN_FULL_TEX: Texture2D = preload("res://assets/sprites/game/fish_full_golden.png")

var _full_tex_before_golden: Texture2D = null


func set_golden(is_golden: bool) -> void:
	var golden := get_node_or_null("Content/FishFull/GoldenFish") as CanvasItem
	if golden != null:
		golden.visible = is_golden
	for n: String in ["Content/FishFull/Star_3", "Content/FishFull/Star_4"]:
		var normal := get_node_or_null(n) as CanvasItem
		if normal != null:
			normal.visible = not is_golden

	var full := get_node_or_null("Content/FishFull/Full") as Sprite2D
	if full == null:
		return
	if is_golden:
		if _full_tex_before_golden == null:
			_full_tex_before_golden = full.texture
		full.texture = GOLDEN_FULL_TEX
	elif _full_tex_before_golden != null:
		full.texture = _full_tex_before_golden
		_full_tex_before_golden = null


func play_revive() -> void:
	var revive_anim := get_node_or_null("AnimLifePlus") as AnimationPlayer
	if revive_anim != null and revive_anim.has_animation("Revive"):
		revive_anim.play("Revive")


func play_collect() -> void:
	if _anim != null and _anim.has_animation(&"Collect"):
		_anim.play(&"Collect")


func play_lost_bounce() -> void:
	if _anim != null and _anim.has_animation(&"Appear_2"):
		_anim.play(&"Appear_2")


const _NEAR_DEATH_GLOW_ANIM: StringName = &"Collect_neardeath"


func play_highlight_glow() -> void:
	if _anim == null or not _anim.has_animation(_NEAR_DEATH_GLOW_ANIM):
		return
	if _anim.is_playing() and _anim.current_animation != _NEAR_DEATH_GLOW_ANIM:
		_anim.seek(_anim.current_animation_length, true)
	_anim.play(_NEAR_DEATH_GLOW_ANIM)


func stop_highlight_glow() -> void:
	if _anim == null or _anim.current_animation != _NEAR_DEATH_GLOW_ANIM:
		return
	_anim.seek(_anim.current_animation_length, true)
	_anim.stop(true)
