## 陪伴猫交互按钮：控制入场动画、布局缩放与点击区域。
extends Button

@export var click_visuals: Array[Control] = []

signal entry_animation_finished

@export var entrance_scale: Vector2 = Vector2.ONE:
	set(value):
		entrance_scale = value
		scale = _layout_scale * entrance_scale

var _layout_scale: Vector2 = Vector2.ONE

@onready
var _entry_animation: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer


func _ready() -> void:
	if _entry_animation == null:
		return
	var source_library: AnimationLibrary = _entry_animation.get_animation_library(&"")
	if source_library == null:
		push_error("HomeCompanionFoodBubble: missing animation library")
		return
	var library: AnimationLibrary = source_library.duplicate(true) as AnimationLibrary
	var animation_names: Array[StringName] = library.get_animation_list()
	for animation_name in animation_names:
		var animation: Animation = library.get_animation(animation_name)
		for track_index in animation.get_track_count():
			var track_path: NodePath = animation.track_get_path(track_index)
			if track_path == NodePath(".:scale:x"):
				animation.track_set_path(track_index, NodePath(".:entrance_scale:x"))
			elif track_path == NodePath(".:scale:y"):
				animation.track_set_path(track_index, NodePath(".:entrance_scale:y"))
	_entry_animation.remove_animation_library(&"")
	if _entry_animation.add_animation_library(&"", library) != OK:
		push_error("HomeCompanionFoodBubble: cannot bind instance animation library")


func set_layout_scale(value: Vector2) -> void:
	if _layout_scale.is_equal_approx(value):
		return
	_layout_scale = value
	scale = _layout_scale * entrance_scale


func play_entry_animation() -> void:
	if _entry_animation == null or not _entry_animation.has_animation(&"appear"):
		push_error("HomeCompanionFoodBubble: missing appear animation")
		return
	_entry_animation.play(&"appear")
	_entry_animation.advance(0.0)


func reset_entry_animation() -> void:
	if _entry_animation != null:
		_entry_animation.stop()
	entrance_scale = Vector2.ONE
	modulate = Color.WHITE


func is_entry_animation_playing() -> bool:
	return _entry_animation != null and _entry_animation.is_playing()


func _on_entry_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"appear":
		entry_animation_finished.emit()


func _has_point(point: Vector2) -> bool:
	if Rect2(Vector2.ZERO, size).has_point(point):
		return true
	for visual in click_visuals:
		if visual.get_rect().has_point(point):
			return true
	return false
