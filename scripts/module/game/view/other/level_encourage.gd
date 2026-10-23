## 关卡鼓励动画准备：为当前鼓励节点配置本次播放的动画资源。
extends Node2D

@export var japanese_textures: Array[Texture2D] = []
@export var animation_player: AnimationPlayer

const _TEXTURE_TRACK: NodePath = ^"Encourage/EncourageImage:texture"
const _SCALE_X_TRACK: NodePath = ^"Encourage/EncourageImage:scale:x"
const _SCALE_Y_TRACK: NodePath = ^"Encourage/EncourageImage:scale:y"
const _JAPANESE_SCALE: float = 0.5


func prepare_animation(level: int, use_japanese: bool) -> StringName:
	var baseline_name: StringName = StringName("Encourage01_%d" % level)
	if not use_japanese:
		return baseline_name
	if level < 1 or level > japanese_textures.size() or japanese_textures[level - 1] == null:
		push_error("LevelEncourage: Japanese texture missing for level %d" % level)
		return baseline_name
	if animation_player == null or not animation_player.has_animation(baseline_name):
		push_error("LevelEncourage: baseline animation missing: %s" % baseline_name)
		return baseline_name
	var animation: Animation = (
		animation_player.get_animation(baseline_name).duplicate() as Animation
	)
	var texture: Texture2D = japanese_textures[level - 1]
	for track_index in animation.get_track_count():
		var track_path: NodePath = animation.track_get_path(track_index)
		for key_index in animation.track_get_key_count(track_index):
			if track_path == _TEXTURE_TRACK:
				animation.track_set_key_value(track_index, key_index, texture)
			elif track_path == _SCALE_X_TRACK or track_path == _SCALE_Y_TRACK:
				var key_data: Array = (
					animation.track_get_key_value(track_index, key_index).duplicate()
				)
				key_data[0] *= _JAPANESE_SCALE
				key_data[2] *= _JAPANESE_SCALE
				key_data[4] *= _JAPANESE_SCALE
				animation.track_set_key_value(track_index, key_index, key_data)
	var library: AnimationLibrary = AnimationLibrary.new()
	var error: Error = library.add_animation(baseline_name, animation)
	if error != OK:
		push_error("LevelEncourage: failed to create Japanese animation: %s" % error)
		return baseline_name
	if animation_player.has_animation_library(&"jp"):
		animation_player.remove_animation_library(&"jp")
	error = animation_player.add_animation_library(&"jp", library)
	if error != OK:
		push_error("LevelEncourage: failed to bind Japanese animation: %s" % error)
		return baseline_name
	return StringName("jp/%s" % baseline_name)
