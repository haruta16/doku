## 排行奖励宝箱的可复用组件；根据名次映射宝箱档位，并维护点击动画与复用重置。

@tool
extends Control

@export var tier: int = 3:
	set(value):
		tier = clampi(value, 1, 3)
		_apply_tier()

@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_apply_tier()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree():
		return
	var pressed: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if not pressed:
		return
	var local: InputEvent = make_input_local(event)
	var pos: Vector2
	if local is InputEventScreenTouch:
		pos = (local as InputEventScreenTouch).position
	elif local is InputEventMouseButton:
		pos = (local as InputEventMouseButton).position
	else:
		return
	if Rect2(Vector2.ZERO, size).has_point(pos):
		play_click()


func set_rank(rank: int) -> void:
	tier = 4 - clampi(rank, 1, 3)


func set_tier(value: int) -> void:
	tier = value


func play_click() -> void:
	if _anim != null and _anim.has_animation(&"Click"):
		_anim.stop()
		_anim.play(&"Click")


## 停止宝箱动画并回到可再次绑定的状态，避免列表回收时保留旧名次的表现。
func reset_for_reuse() -> void:
	if Engine.is_editor_hint():
		return
	var players: Array[Node] = find_children("*", "AnimationPlayer", true, false)
	for node: Node in players:
		var player: AnimationPlayer = node as AnimationPlayer
		player.stop(true)
		if player.has_animation(&"RESET"):
			player.assigned_animation = &"RESET"
	var sprites: Array[Node] = find_children("*", "SpineSprite", true, false)
	for node: Node in sprites:
		var sprite: SpineSprite = node as SpineSprite
		var state: SpineAnimationState = sprite.get_animation_state()
		if state != null:
			state.clear_tracks()
		var skeleton: SpineSkeleton = sprite.get_skeleton()
		if skeleton != null:
			skeleton.set_to_setup_pose()


func _apply_tier() -> void:
	var skin: String = "RankBox%d" % tier
	for sp: SpineSprite in [
		get_node_or_null("Tier/SpineSprite3") as SpineSprite,
		get_node_or_null("Tier/SpineSprite4") as SpineSprite,
	]:
		if sp == null:
			continue
		if Engine.is_editor_hint():
			sp.preview_skin = skin
			continue
		var sk = sp.get_skeleton()
		if sk == null:
			continue
		sk.set_skin_by_name(skin)
		sk.set_slots_to_setup_pose()
