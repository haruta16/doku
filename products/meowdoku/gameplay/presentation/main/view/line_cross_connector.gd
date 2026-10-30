## 划线连接特效：按端点更新几何，播放连线与中点动画并支持停止重建。
@tool
class_name LineCrossConnector
extends Control

@export_group("Line")
@export var line_texture: Texture2D
@export_range(0.0, 512.0, 1.0) var line_display_height: float = 32.0
@export_range(-256.0, 256.0, 1.0) var line_end_extension: float = 0.0

@export_group("Midpoint")
@export var midpoint_offset: Vector2 = Vector2.ZERO
@export var rotate_midpoint_with_line: bool = false
@export var midpoint_animation_name: StringName

@export_group("Playback")
@export var autoplay: bool = true

@onready var _point_a: Marker2D = $A
@onready var _point_b: Marker2D = $B
@onready var _line: Sprite2D = $Line
@onready var _midpoint_slot: Node2D = $MidpointSlot
@onready var _anim_player: AnimationPlayer = $AnimationPlayer

var _is_playing: bool = false


func _ready() -> void:
	_is_playing = autoplay
	_update_layout()
	_apply_visibility()


func _process(_delta: float) -> void:
	_update_layout()


func setup_points(a_local: Vector2, b_local: Vector2) -> void:
	_point_a.position = a_local
	_point_b.position = b_local


func play_effect() -> void:
	_is_playing = true
	_update_layout()
	_apply_visibility()
	_play_midpoint_animation()


func regenerate() -> void:
	play_effect()


func stop_effect() -> void:
	_is_playing = false
	_apply_visibility()


func get_midpoint_slot() -> Node2D:
	return _midpoint_slot


func _update_layout() -> void:
	if not is_instance_valid(_point_a) or not is_instance_valid(_point_b):
		return

	var start: Vector2 = _point_a.position
	var finish: Vector2 = _point_b.position
	var midpoint: Vector2 = start.lerp(finish, 0.5)
	var delta: Vector2 = finish - start
	var distance: float = delta.length()
	var angle: float = delta.angle() if not is_zero_approx(distance) else 0.0

	_midpoint_slot.position = midpoint + midpoint_offset
	_midpoint_slot.rotation = angle if rotate_midpoint_with_line else 0.0

	_line.texture = line_texture
	_line.position = midpoint
	if line_texture == null or is_zero_approx(distance):
		_line.visible = false
		return

	var texture_size: Vector2 = line_texture.get_size()
	var display_length: float = maxf(distance + line_end_extension * 2.0, 0.0)
	_line.rotation = angle
	_line.scale = Vector2(
		display_length / maxf(texture_size.x, 1.0), line_display_height / maxf(texture_size.y, 1.0)
	)
	_line.visible = _is_playing or Engine.is_editor_hint()


func _apply_visibility() -> void:
	var shown: bool = _is_playing or Engine.is_editor_hint()
	_midpoint_slot.visible = shown
	_line.visible = shown and line_texture != null


func _play_midpoint_animation() -> void:
	if midpoint_animation_name.is_empty():
		return
	if not _anim_player.has_animation(midpoint_animation_name):
		push_warning("LineCrossConnector: 找不到中点动画 %s" % midpoint_animation_name)
		return
	_anim_player.play(midpoint_animation_name)
