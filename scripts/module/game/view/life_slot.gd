class_name LifeSlot
extends Control

@onready var _anim: AnimationPlayer = $AnimationPlayer
var _is_lost: bool = false


func mark_lost() -> void:
	_is_lost = true


func show_alive() -> void:
	_is_lost = false
	if _anim != null:
		_anim.play("RESET")
		_anim.seek(_anim.current_animation_length, true)


func show_lost(animate: bool) -> void:
	if _anim == null:
		return
	if not animate and _is_lost:
		return
	_is_lost = true
	_anim.play("Appear")
	if not animate:
		_anim.seek(_anim.current_animation_length, true)


func play_revive() -> void:
	var life_plus_anim := get_node_or_null("AnimLifePlus") as AnimationPlayer
	if life_plus_anim != null and life_plus_anim.has_animation("Revive"):
		life_plus_anim.play("Revive")
