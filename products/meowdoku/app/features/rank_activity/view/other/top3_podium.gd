## 前三名领奖台；组合身份、鱼数、点赞与在线标签，提供挂载头像和滚动分数的表现入口。

extends Control

signal like_heart_pressed(robot_id: String)

const _RANK_COUNT: int = 3
const _LIKE_FISH_X: float = -7.5
const _EMPTY_HEART_ALPHA: float = 0.6
const _UNLIKED_INNER_NUMBER_ALPHA: float = 0.8

const _PODIUM_COLUMN_WIDTH: float = 325.0

const _ONLINE_TAG_MAX_WIDTH: float = 280.0

const _NAME_TIGHT_DELTA: float = -10.0
const _FISH_TIGHT_DELTA: float = -20.0
const _BOX_TIGHT_DELTA: float = -29.0

var _layout_baseline: Dictionary = {}

var _fish_tweens: Array = [null, null, null]
var _fish_finals: Array[int] = [0, 0, 0]
var _fish_base_x: Array[float] = [0.0, 0.0, 0.0]


func _ready() -> void:
	for rank in range(1, _RANK_COUNT + 1):
		var fish: Control = get_node_or_null("Rank%d/Info/Fish" % rank) as Control
		if fish != null:
			_fish_base_x[rank - 1] = fish.position.x
		set_like_display(rank, false)


func apply(rank: int, id_text: String, fish_count: int) -> void:
	var node := get_node_or_null("Rank%d" % rank) as Control
	if node == null:
		return
	var idx: int = rank - 1
	if idx >= 0 and idx < _fish_tweens.size():
		var t: Tween = _fish_tweens[idx] as Tween
		if t != null and t.is_valid():
			t.kill()
		_fish_tweens[idx] = null

		_fish_finals[idx] = 0
	var id_label := node.get_node_or_null("Info/PlayerId") as Label
	if id_label != null:
		id_label.text = id_text
	var fish_label := node.get_node_or_null("Info/Fish/FishCount") as Label
	if fish_label != null:
		fish_label.text = str(fish_count)


func set_like_display(
	rank: int,
	shown: bool,
	heart_count: int = 0,
	filled: bool = false,
	target_id: String = "",
	animate: bool = false
) -> void:
	if rank < 1 or rank > _RANK_COUNT:
		return
	var index: int = rank - 1
	var fish: Control = get_node_or_null("Rank%d/Info/Fish" % rank) as Control
	if fish != null:
		fish.position.x = _LIKE_FISH_X if shown else _fish_base_x[index]
	var heart: RankHeart = get_node_or_null("Rank%d/Info/Heart" % rank) as RankHeart
	if heart == null:
		return
	heart.configure_like_display(
		shown,
		heart_count,
		filled,
		true,
		target_id,
		animate,
		_on_heart_pressed,
		_EMPTY_HEART_ALPHA,
		_UNLIKED_INNER_NUMBER_ALPHA
	)


func refresh_robot_like_display(
	target_id: String, heart_count: int, filled: bool, animate: bool = false
) -> void:
	if target_id.is_empty():
		return
	for rank in range(1, _RANK_COUNT + 1):
		var heart: RankHeart = get_node_or_null("Rank%d/Info/Heart" % rank) as RankHeart
		if heart != null and heart.is_like_target(target_id):
			set_like_display(rank, true, heart_count, filled, target_id, animate)


func _on_heart_pressed(robot_id: String) -> void:
	like_heart_pressed.emit(robot_id)


func get_avatar_mount(rank: int) -> Control:
	return get_node_or_null("Rank%d/AvatarGroup" % rank) as Control


func set_online_layout(tight: bool, tag_top: float) -> void:
	for rank in range(1, _RANK_COUNT + 1):
		_apply_column_layout(rank, tight)
		var tag: Control = get_node_or_null("Rank%d/OnlineTag" % rank) as Control
		if tag != null:
			var tag_height: float = tag.offset_bottom - tag.offset_top
			tag.offset_top = tag_top
			tag.offset_bottom = tag_top + tag_height


func apply_online(
	rank: int, show: bool, is_online: bool, idle_sec: int, is_self: bool = false
) -> void:
	var tag: Panel = get_node_or_null("Rank%d/OnlineTag" % rank) as Panel
	if tag == null:
		return
	if not show:
		tag.visible = false
		return
	tag.apply(is_online, idle_sec, _ONLINE_TAG_MAX_WIDTH, is_self)

	var tag_width: float = tag.size.x
	tag.offset_left = (_PODIUM_COLUMN_WIDTH - tag_width) * 0.5
	tag.offset_right = tag.offset_left + tag_width


func _apply_column_layout(rank: int, tight: bool) -> void:
	var name_label: Control = get_node_or_null("Rank%d/Info/PlayerId" % rank) as Control
	var fish: Control = get_node_or_null("Rank%d/Info/Fish" % rank) as Control
	var box: Control = get_node_or_null("Rank%d/Podium/TreasureBox" % rank) as Control
	if not _layout_baseline.has(rank):
		_layout_baseline[rank] = {
			"name_top": name_label.offset_top if name_label != null else 0.0,
			"fish_top": fish.offset_top if fish != null else 0.0,
			"box_top": box.offset_top if box != null else 0.0,
		}
	var baseline: Dictionary = _layout_baseline[rank]
	if name_label != null:
		var name_height: float = name_label.offset_bottom - name_label.offset_top
		name_label.offset_top = float(baseline.name_top) + (_NAME_TIGHT_DELTA if tight else 0.0)
		name_label.offset_bottom = name_label.offset_top + name_height
	if fish != null:
		var fish_height: float = fish.offset_bottom - fish.offset_top
		fish.offset_top = float(baseline.fish_top) + (_FISH_TIGHT_DELTA if tight else 0.0)
		fish.offset_bottom = fish.offset_top + fish_height
	if box != null:
		var box_height: float = box.offset_bottom - box.offset_top
		box.offset_top = float(baseline.box_top) + (_BOX_TIGHT_DELTA if tight else 0.0)
		box.offset_bottom = box.offset_top + box_height


func set_show_box(show: bool) -> void:
	for r in _RANK_COUNT:
		var box := get_node_or_null("Rank%d/Podium/TreasureBox" % (r + 1)) as CanvasItem
		if box != null:
			box.visible = show


func get_collection_mount(rank: int) -> Control:
	return get_node_or_null("Rank%d/Info/Fish" % rank) as Control


func get_fish_icon(rank: int) -> Control:
	return get_node_or_null("Rank%d/Info/Fish/PropIcon/Fish" % rank) as Control


func get_fish_icon_global(rank: int) -> Vector2:
	var icon := get_node_or_null("Rank%d/Info/Fish/PropIcon/Fish" % rank) as Control
	if icon == null or not is_instance_valid(icon):
		push_error(
			"top3_podium: Rank%d 缺 Info/Fish/PropIcon/Fish,鱼干飞行终点定位失败 → 返回 Vector2.ZERO" % rank
		)
		return Vector2.ZERO
	var s: Vector2 = icon.get_global_transform().get_scale()
	return icon.global_position + icon.size * s / 2.0


func set_fish_icon_above_z(rank: int, z: int) -> void:
	var icon := get_node_or_null("Rank%d/Info/Fish/PropIcon/Fish" % rank) as Control
	if icon != null and is_instance_valid(icon):
		icon.z_index = z
	else:
		push_error("top3_podium: Rank%d 缺 Info/Fish/PropIcon/Fish,无法抬起 z_index" % rank)


func roll_fish(rank: int, from_v: int, to_v: int, dur: float) -> void:
	var node := get_node_or_null("Rank%d" % rank) as Control
	if node == null:
		return
	var fish_label := node.get_node_or_null("Info/Fish/FishCount") as Label
	if fish_label == null:
		return
	var idx: int = rank - 1
	if idx >= 0 and idx < _fish_tweens.size():
		var old_t: Tween = _fish_tweens[idx] as Tween
		if old_t != null and old_t.is_valid():
			old_t.kill()
		_fish_tweens[idx] = null
		_fish_finals[idx] = to_v
	if dur <= 0.0 or from_v == to_v:
		fish_label.text = str(to_v)
		return
	fish_label.text = str(from_v)
	var setter := func(v: float) -> void: fish_label.text = str(int(round(v)))
	var t: Tween = create_tween()
	t.tween_method(setter, float(from_v), float(to_v), dur).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_QUAD
	)
	if idx >= 0 and idx < _fish_tweens.size():
		_fish_tweens[idx] = t


func finalize_fish_roll(rank: int) -> void:
	var idx: int = rank - 1
	if idx < 0 or idx >= _fish_tweens.size():
		return
	var t: Tween = _fish_tweens[idx] as Tween
	var had_roll: bool = t != null and t.is_valid()
	if had_roll:
		t.kill()
	_fish_tweens[idx] = null

	if had_roll or _fish_finals[idx] != 0:
		var node := get_node_or_null("Rank%d" % rank) as Control
		if node != null:
			var fish_label := node.get_node_or_null("Info/Fish/FishCount") as Label
			if fish_label != null:
				fish_label.text = str(_fish_finals[idx])
