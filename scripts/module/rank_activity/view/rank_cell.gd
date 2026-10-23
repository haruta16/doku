## 可复用排行榜行；显示身份、分数、在线、点赞和宝箱，并承接入场、升名次与收集动画。
## 一行节点会先后绑定不同玩家，因此 reset_for_reuse 必须清理上一条数据留下的表现状态。

extends UIChildWindow
class_name RankCell

signal like_heart_pressed(robot_id: String)

const AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _AVATAR_SCALE: float = 160.0 / 185.0

const _COLOR_NORMAL: Color = Color(0.5769231, 0.3522559, 0.3522559, 1)
const _COLOR_SELF: Color = Color(0.77403843, 0.36206105, 0.2366766, 1)

const _NAME_TOP_ALONE: float = 5.0
const _NAME_TOP_WITH_TAG: float = -19.0

const _ONLINE_TAG_MAX_WIDTH: float = 270.0

const _SHADOW_BASE_OFFSET_TOP: float = -51.0
const _SHADOW_FLIP_OFFSET_TOP: float = -41.45
const _EMPTY_HEART_ALPHA: float = 0.3

const _SHADOW_FADE_DUR: float = 0.15

@onready var _bg_normal: TextureRect = $Root/CanvasGroup/BgNormal
@onready var _bg_self: TextureRect = $Root/CanvasGroup/BgSelf
@onready var _bg_self_shadow: NinePatchRect = $Root/Shadow
@onready var _big_medal: TextureRect = $Root/CanvasGroup/BigMedal
@onready var _avatar_slot: Control = $Root/CanvasGroup/Content/AvatarSlot
@onready var _name_label: Label = $Root/CanvasGroup/Content/NameLabel
@onready var _fish_count: Label = $Root/CanvasGroup/Content/Fish/CountLabel
@onready var _fish_count_bg: TextureRect = $Root/CanvasGroup/Content/Fish/CountBg
@onready var _fish_icon: TextureRect = $Root/CanvasGroup/Content/Fish/FishIcon
@onready var _heart: RankHeart = $Root/CanvasGroup/Content/Heart
@onready var _rank_plain: Label = $Root/CanvasGroup/Content/RankPlain

@onready var _online_tag: Panel = $Root/CanvasGroup/Content/OnlineTag
@onready var _chest: Control = $Root/CanvasGroup/Content/Chest
@onready var _medal_badge: Control = $Root/CanvasGroup/MedalBadge
@onready var _medal_badge_bg: TextureRect = $Root/CanvasGroup/MedalBadge/BadgeBg
@onready var _medal_badge_num: Label = $Root/CanvasGroup/MedalBadge/BadgeNum

@export var big_medal_textures: Array[Texture2D] = []

@export var medal_badge_textures: Array[Texture2D] = []

@export var fish_count_bg_normal: Texture2D = null

@export var fish_count_bg_self: Texture2D = null

var _avatar: Control = null

var _show_chest: bool = true

@onready var _anim: AnimationPlayer = $AnimationPlayer

var _full_animation_library: AnimationLibrary = null

const _COLLECTION_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/other/rank_change_collection.tscn"
)

const _PARTICLES_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/other/rank_cell_particles.tscn"
)
@onready var _root: Control = $Root
var _particles: Node = null
var _collection: Node = null
var _collection_appear: AnimationPlayer = null

const _COLLECT_FISH_ICON: Texture2D = preload("res://assets/sprites/rank_activity/collect_fish.png")

const _SCORE_FISH_ICON: Texture2D = preload("res://assets/sprites/rank_activity/rank_fish_icon.png")

const _LABEL_BATCH_Z: int = 1

var _arrow: Control = null
var _arrow_particle: CPUParticles2D = null
var _arrow_tween: Tween = null

var _shadow_shown: bool = false
var _shadow_tween: Tween = null
var _has_online_display_state: bool = false
var _last_online_shown: bool = false
var _last_online_state: bool = false
var _last_online_idle_sec: int = 0
var _last_online_is_self: bool = false
var _last_online_self_offline: bool = false
var _has_like_display_state: bool = false
var _last_like_shown: bool = false
var _last_like_heart_count: int = 0
var _last_like_filled: bool = false
var _last_like_target_id: String = ""

const _COLLECT_BURST_SCENE: PackedScene = preload("res://assets/prefab/effect_score_burst.tscn")


func _ready() -> void:
	super._ready()
	_prepare_lazy_animation_library()

	_avatar = AVATAR_CELL.instantiate()
	_avatar.scale = Vector2(_AVATAR_SCALE, _AVATAR_SCALE)
	_avatar_slot.add_child(_avatar)

	if _bg_self_shadow != null:
		_bg_self_shadow.modulate.a = 0.0

	visibility_changed.connect(_on_shadow_visibility_changed)
	set_like_display(false)


func _prepare_lazy_animation_library() -> void:
	_full_animation_library = _anim.get_animation_library(&"")
	if _full_animation_library == null:
		push_error("RankCell: missing animation library")
		return
	var library: AnimationLibrary = AnimationLibrary.new()
	var animation_names: Array[StringName] = _full_animation_library.get_animation_list()
	for animation_name: StringName in animation_names:
		var source: Animation = _full_animation_library.get_animation(animation_name)
		var animation: Animation = source
		for track_index in source.get_track_count():
			var track_path: String = String(source.track_get_path(track_index))
			if (
				track_path.begins_with("Root/Particles/")
				or track_path.begins_with("Root/Particles:")
			):
				animation = source.duplicate() as Animation
				break
		if animation != source:
			for track_index in range(animation.get_track_count() - 1, -1, -1):
				var track_path: String = String(animation.track_get_path(track_index))
				if (
					track_path.begins_with("Root/Particles/")
					or track_path.begins_with("Root/Particles:")
				):
					animation.remove_track(track_index)
		if library.add_animation(animation_name, animation) != OK:
			push_error("RankCell: cannot add animation %s" % animation_name)
	_anim.remove_animation_library(&"")
	if _anim.add_animation_library(&"", library) != OK:
		push_error("RankCell: cannot install lazy animation library")


## 设置名次、昵称、分数与高亮样式；头像等完整身份信息由 set_player 另行绑定。
func set_entry(rank: int, is_self: bool, display_name: String, fish_count: int) -> void:
	_name_label.text = display_name
	_fish_count.text = str(fish_count)
	_apply_style(rank, is_self)


func set_online(
	show: bool, is_online: bool, idle_sec: int, is_self: bool = false, self_offline: bool = false
) -> void:
	if _online_tag == null:
		return
	if (
		_has_online_display_state
		and _last_online_shown == show
		and _last_online_state == is_online
		and _last_online_idle_sec == idle_sec
		and _last_online_is_self == is_self
		and _last_online_self_offline == self_offline
	):
		return
	_has_online_display_state = true
	_last_online_shown = show
	_last_online_state = is_online
	_last_online_idle_sec = idle_sec
	_last_online_is_self = is_self
	_last_online_self_offline = self_offline
	if not show:
		_online_tag.visible = false
		_apply_name_top(_NAME_TOP_ALONE)
		return
	_apply_name_top(_NAME_TOP_WITH_TAG)
	_online_tag.apply(is_online, idle_sec, _ONLINE_TAG_MAX_WIDTH, is_self, self_offline)


func _apply_name_top(offset_top: float) -> void:
	if _name_label == null:
		return
	var height: float = _name_label.offset_bottom - _name_label.offset_top
	_name_label.offset_top = offset_top
	_name_label.offset_bottom = offset_top + height


func set_like_display(
	shown: bool,
	heart_count: int = 0,
	filled: bool = false,
	target_id: String = "",
	animate: bool = false
) -> void:
	if (
		not animate
		and _has_like_display_state
		and _last_like_shown == shown
		and _last_like_heart_count == heart_count
		and _last_like_filled == filled
		and _last_like_target_id == target_id
	):
		return
	_has_like_display_state = true
	_last_like_shown = shown
	_last_like_heart_count = heart_count
	_last_like_filled = filled
	_last_like_target_id = target_id
	_heart.configure_like_display(
		shown, heart_count, filled, false, target_id, animate, _on_heart_pressed, _EMPTY_HEART_ALPHA
	)


func _on_heart_pressed(robot_id: String) -> void:
	like_heart_pressed.emit(robot_id)


func set_self_shadow(shown: bool, flip_v: bool = false) -> void:
	if _bg_self_shadow == null:
		return

	if shown:
		_bg_self_shadow.pivot_offset = _bg_self_shadow.size * 0.5
		if flip_v:
			_bg_self_shadow.scale.y = -1.0
			_bg_self_shadow.position.y = _SHADOW_FLIP_OFFSET_TOP
		else:
			_bg_self_shadow.scale.y = 1.0
			_bg_self_shadow.position.y = _SHADOW_BASE_OFFSET_TOP

	if shown == _shadow_shown:
		return
	_shadow_shown = shown

	if _shadow_tween != null and _shadow_tween.is_valid():
		_shadow_tween.kill()
	if shown:
		_bg_self_shadow.visible = true
		_shadow_tween = create_tween()
		_shadow_tween.tween_property(_bg_self_shadow, "modulate:a", 1.0, _SHADOW_FADE_DUR)
	else:
		_shadow_tween = create_tween()
		_shadow_tween.tween_property(_bg_self_shadow, "modulate:a", 0.0, _SHADOW_FADE_DUR)
		_shadow_tween.tween_callback(_hide_shadow_node)


func _hide_shadow_node() -> void:
	if _bg_self_shadow != null:
		_bg_self_shadow.visible = false


func _on_shadow_visibility_changed() -> void:
	if is_visible_in_tree():
		return
	if _shadow_tween != null and _shadow_tween.is_valid():
		_shadow_tween.kill()
	_shadow_tween = null
	_shadow_shown = false
	if _bg_self_shadow != null:
		_bg_self_shadow.visible = false
		_bg_self_shadow.modulate.a = 0.0


func set_score(count: int) -> void:
	_fish_count.text = str(count)


func set_rank_number(rank: int) -> void:
	var txt: String = str(rank) if rank >= 1 else "-"
	_rank_plain.text = txt
	_medal_badge_num.text = txt


func apply_score_icon() -> void:
	_fish_icon.texture = _SCORE_FISH_ICON


func enable_label_z_batching() -> void:
	for label: Node in _root.find_children("*", "Label", true, false):
		(label as Label).z_index = _LABEL_BATCH_Z


func get_fish_icon_global() -> Vector2:
	var s: Vector2 = _fish_icon.get_global_transform().get_scale()
	return _fish_icon.global_position + _fish_icon.size * s / 2.0


func set_fish_icon_above_z(z: int) -> void:
	if _fish_icon != null:
		_fish_icon.z_index = z


func emit_fish_collect_burst(before_start: Callable = Callable()) -> void:
	if _fish_icon == null:
		return
	var burst: Node = _COLLECT_BURST_SCENE.instantiate()
	_fish_icon.add_child(burst)
	if burst is Control:
		(burst as Control).position = _fish_icon.size * 0.5
	elif burst is Node2D:
		(burst as Node2D).position = _fish_icon.size * 0.5
	if before_start.is_valid():
		before_start.call(burst)
	var max_life: float = 0.0
	for p: Node in burst.find_children("*", "CPUParticles2D", true, false):
		var particle := p as CPUParticles2D
		if particle != null:
			particle.restart()
			particle.emitting = true
			max_life = maxf(max_life, particle.lifetime)
	var tw: Tween = burst.create_tween()
	tw.tween_interval(max_life + 0.3)
	tw.tween_callback(burst.queue_free)


func set_show_chest(show: bool) -> void:
	_show_chest = show


func get_avatar_cell() -> Control:
	return _avatar


func set_player(info: PlayerInfo) -> void:
	if _avatar != null and info != null:
		_avatar.apply_player_info(info)


func play_intro(anim_name: StringName) -> void:
	_root.modulate.a = 1.0
	AnimUtil.play(_anim, anim_name)


func prepare_intro() -> void:
	_anim.pause()
	_root.modulate.a = 0.0


func show_static() -> void:
	AnimUtil.play(_anim, &"Idle", false)


## 停止动画并恢复可复用基线；下一条排行数据不能继承上一个玩家的特效、阴影或交互状态。
func reset_for_reuse() -> void:
	finish_collection_now()
	if _shadow_tween != null:
		_shadow_tween.kill()
	_shadow_tween = null
	_shadow_shown = false
	var nodes: Array[Node] = find_children("*", "", true, false)
	for node: Node in nodes:
		if _chest.is_ancestor_of(node):
			continue
		if node is AnimationPlayer:
			(node as AnimationPlayer).stop()
		elif node is CPUParticles2D:
			(node as CPUParticles2D).emitting = false
		elif node is GPUParticles2D:
			(node as GPUParticles2D).emitting = false
	_chest.reset_for_reuse()
	hide_arrow()
	_root.position = Vector2.ZERO
	_root.scale = Vector2.ONE
	_root.rotation = 0.0
	_root.modulate = Color.WHITE
	_root.self_modulate = Color.WHITE
	var group: Control = $Root/CanvasGroup
	group.position = Vector2.ZERO
	group.scale = Vector2.ONE
	group.rotation = 0.0
	group.modulate = Color.WHITE
	group.self_modulate = Color.WHITE
	_bg_self_shadow.visible = false
	_bg_self_shadow.modulate.a = 0.0
	_bg_self_shadow.scale = Vector2.ONE
	_bg_self_shadow.position.y = _SHADOW_BASE_OFFSET_TOP
	_has_online_display_state = false
	_has_like_display_state = false
	set_online(false, false, 0)
	set_like_display(false)
	set_show_chest(true)
	set_entry(0, false, "", 0)
	set_fish_icon_above_z(0)
	set_effect_z(0)
	if _avatar != null:
		_avatar.position = Vector2.ZERO
		_avatar.scale = Vector2(_AVATAR_SCALE, _AVATAR_SCALE)
		_avatar.pivot_offset = Vector2.ZERO
		_avatar.rotation = 0.0
		_avatar.modulate = Color.WHITE
		_avatar.set_base_visible(true)
		_avatar.set_avatar_visible(true)
		_avatar.set_red_dot(false)
		_avatar.set_info(0, 0)
		_avatar.show_count_static(-1)
		_avatar.set_count(-1)
	remove_meta(&"is_self")


func play_lift() -> void:
	_ensure_particles()

	SoundManager.play(SoundManager.Kind.RANK_RISE_UP)

	_anim.play(&"Rise_Up")
	await _anim.animation_finished


func play_intro_and_wait(anim_name: StringName) -> void:
	AnimUtil.play(_anim, anim_name)
	await _anim.animation_finished


func play_rise_idle() -> void:
	_ensure_particles()
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	var idle: Animation = _anim.get_animation(&"Rise_Idle")
	if idle != null:
		idle.loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Rise_Idle")


func play_drop() -> void:
	_ensure_particles()

	SoundManager.play(SoundManager.Kind.RANK_RISE_DOWN)
	_anim.play(&"Rise_Down")
	await _anim.animation_finished


func _ensure_particles() -> void:
	if _particles != null and is_instance_valid(_particles):
		return
	if _root == null:
		return
	var inst: Node = _PARTICLES_SCENE.instantiate()
	inst.name = "Particles"
	_root.add_child(inst)
	_particles = inst
	_arrow = inst.get_node_or_null("Arrow") as Control
	_arrow_particle = inst.get_node_or_null("Arrow/Arrow") as CPUParticles2D
	if _full_animation_library != null:
		_anim.remove_animation_library(&"")
		if _anim.add_animation_library(&"", _full_animation_library) != OK:
			push_error("RankCell: cannot restore particle animation library")
		_anim.clear_caches()


func set_effect_z(z: int) -> void:
	if _particles != null and is_instance_valid(_particles):
		(_particles as CanvasItem).z_index = z


func _ensure_collection() -> void:
	if _collection != null and is_instance_valid(_collection):
		return
	_ensure_particles()
	if _particles == null:
		return
	var inst: Control = _COLLECTION_SCENE.instantiate()
	inst.z_index = 25
	inst.offset_left = 888.0
	inst.offset_top = 90.0
	inst.offset_right = 928.0
	inst.offset_bottom = 129.99998

	var layouts: Array = [
		Vector2(-5, -52),
		Vector2(40, -30),
		Vector2(-25, 35),
		Vector2(35, 30),
		Vector2(-40, -15),
		Vector2(3, -2),
	]
	for i in range(layouts.size()):
		var sp := inst.get_node_or_null("Collection%d" % (i + 1)) as Node2D
		if sp != null:
			sp.position = layouts[i]
			sp.scale = Vector2(0.3, 0.3)
	_particles.add_child(inst)
	_collection = inst
	_collection_appear = inst.get_node_or_null("CollectionAppear") as AnimationPlayer


var _count_gen: int = 0


func play_count() -> void:
	_ensure_collection()
	if _collection_appear == null or not _collection_appear.has_animation(&"Count"):
		return

	SoundManager.play(SoundManager.Kind.RANK_SCORE_COUNT)
	_collection_appear.play(&"Count")

	_count_gen += 1
	var gen: int = _count_gen
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			if gen != _count_gen:
				return
			VibrateManager.play_at(VibrateManager.Pos.RANK_CELL_FLY)
	)
	await _collection_appear.animation_finished


func await_collection_finished() -> void:
	if _collection_appear != null and _collection_appear.is_playing():
		await _collection_appear.animation_finished


func snap_idle() -> void:
	AnimUtil.play(_anim, &"Idle", true)


func snap_rise_down_start() -> void:
	AnimUtil.play(_anim, &"Rise_Down", true)


## 立即完成收集表现并回到稳定外观，供页面快进或列表回收时收尾。
func finish_collection_now() -> void:
	_count_gen += 1

	if _collection_appear != null and _collection_appear.is_playing():
		var cur: StringName = _collection_appear.current_animation
		if cur != StringName():
			var anim: Animation = _collection_appear.get_animation(cur)
			if anim != null:
				var remain: float = anim.length - _collection_appear.current_animation_position
				if remain > 0.0:
					_collection_appear.advance(remain + 0.001)

	if _collection != null and is_instance_valid(_collection) and _collection is CanvasItem:
		(_collection as CanvasItem).visible = false

	if _collection != null and is_instance_valid(_collection):
		var children: Array[Node] = _collection.get_children()
		for c: Node in children:
			if c is Sprite2D:
				var m: Color = (c as Sprite2D).modulate
				m.a = 0.0
				(c as Sprite2D).modulate = m


func set_collection_visual() -> void:
	_ensure_collection()
	var tex: Texture2D = _COLLECT_FISH_ICON
	if _collection == null or tex == null:
		return
	for c in _collection.get_children():
		if c is Sprite2D:
			(c as Sprite2D).texture = tex


static func collect_fish_texture() -> Texture2D:
	return _COLLECT_FISH_ICON


func play_arrow(fade_dur: float = 0.5) -> void:
	_ensure_particles()
	if _arrow == null:
		return
	if _arrow_particle != null:
		_arrow_particle.restart()
		_arrow_particle.emitting = true
	_arrow.modulate.a = 1.0
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = create_tween()
	_arrow_tween.tween_property(_arrow, "modulate:a", 0.0, maxf(0.01, fade_dur))


func hide_arrow() -> void:
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	if _arrow != null:
		_arrow.modulate.a = 0.0
	if _arrow_particle != null:
		_arrow_particle.emitting = false


func _apply_style(rank: int, is_self: bool) -> void:
	var is_top3: bool = rank >= 1 and rank <= 3

	_bg_normal.visible = not is_self
	_bg_self.visible = is_self
	if is_self:
		set_self_shadow(false)

	var text_color: Color = _COLOR_SELF if is_self else _COLOR_NORMAL
	_name_label.add_theme_color_override("font_color", text_color)
	_fish_count_bg.texture = fish_count_bg_self if is_self else fish_count_bg_normal

	_rank_plain.visible = not is_top3
	if not is_top3:
		_rank_plain.text = str(rank) if rank >= 1 else "-"
		_rank_plain.add_theme_color_override("font_color", text_color)

	_big_medal.visible = is_top3
	_medal_badge.visible = is_top3

	_chest.visible = is_top3 and _show_chest
	if is_top3:
		var idx: int = rank - 1
		_big_medal.texture = big_medal_textures[idx] if idx < big_medal_textures.size() else null
		_medal_badge_bg.texture = (
			medal_badge_textures[idx] if idx < medal_badge_textures.size() else null
		)
		_chest.set_rank(rank)
		_medal_badge_num.text = str(rank)
