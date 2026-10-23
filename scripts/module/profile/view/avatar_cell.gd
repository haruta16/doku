## 可复用头像组件；组合头像、边框、获奖次数和红点，并提供次数增长与摇动动画。

extends UIChildWindow

@onready var _base: TextureRect = $Base
@onready var _avatar: TextureRect = $Base/Avatar
@onready var _frame: TextureRect = $Frame
@onready var _red_dot: TextureRect = $RedDot
@onready var _count_badge: Label = $Frame/Clip/CountBadge
@onready var _count_badge_new: Label = $Frame/Clip/CountBadgeNew
@onready var _count_anim: AnimationPlayer = $AnimationPlayer

@export var avatar_textures: Array[Texture2D] = []

@export var frame_textures: Array[Texture2D] = []

var _is_self: bool = false

var _frame_id: int = 0

@onready var _count_font_size: int = _count_badge.get_theme_font_size(&"font_size")


func on_show(_params: Dictionary = {}) -> void:
	if _is_self:
		_apply_self()


func set_self() -> void:
	_is_self = true
	_apply_self()


## 将共用身份模型拆成头像、边框和次数显示；支持本机玩家与机器人使用同一种组件。
func apply_player_info(info: PlayerInfo) -> void:
	if info == null:
		return
	_is_self = info.is_self()
	var frame_id: int = info.frame.id if info.frame != null else 0
	var form: int = info.frame.form if info.frame != null else 0
	set_info(info.avatar_id, frame_id, form)

	set_count(
		(
			info.frame.acquired_count
			if info.frame != null and ProfileCatalog.shows_frame_count(frame_id)
			else -1
		)
	)


func set_info(avatar_id: int, frame_id: int, form: int = 0) -> void:
	set_avatar(avatar_id)
	set_frame(frame_id, form)


func set_avatar(avatar_id: int) -> void:
	var idx: int = _avatar_index(avatar_id)
	_avatar.texture = avatar_textures[idx] if idx >= 0 and idx < avatar_textures.size() else null


func set_frame(frame_id: int, form: int = 0) -> void:
	if form != 0 and not ABTestManager.rank_1st_frame.is_enabled():
		form = 0
	_frame_id = frame_id
	var idx: int = _frame_index(frame_id, form)
	if idx >= 0 and idx < frame_textures.size():
		_frame.texture = frame_textures[idx]
		_frame.visible = true
	else:
		_frame.texture = null
		_frame.visible = false
	set_count(ProfileService.get_frame_count(frame_id))


func set_base_visible(shown: bool) -> void:
	_base.visible = shown


func set_base_texture_visible(shown: bool) -> void:
	_base.self_modulate.a = 1.0 if shown else 0.0


func set_avatar_visible(shown: bool) -> void:
	_avatar.visible = shown


func set_frame_visible(shown: bool) -> void:
	_frame.visible = shown


func set_count(count: int) -> void:
	if count >= 1 and ProfileCatalog.shows_frame_count(_frame_id):
		_count_badge.text = str(count)
		_fit_count_badges()
		_count_badge.visible = true
	else:
		_count_badge.visible = false


func set_count_forced(count: int) -> void:
	_count_badge.text = str(count)
	_fit_count_badges()
	_count_badge.visible = true


func show_count_static(count: int) -> void:
	if _count_badge != null:
		_count_badge.position = Vector2(4, -5)
	if _count_badge_new != null:
		_count_badge_new.position = Vector2(4, 15)
	_count_badge.text = str(count)
	_fit_count_badges()
	_count_badge.visible = true
	if _count_badge_new != null:
		_count_badge_new.visible = false


## 把展示次数从旧值动画过渡到新值；实际获奖次数的持久化已由业务层完成。
func play_count_increase(before: int, after: int) -> AnimationPlayer:
	_count_badge.text = str(before)
	_count_badge.visible = true
	if _count_badge_new != null:
		_count_badge_new.text = str(after)
		_count_badge_new.visible = true
	_fit_count_badges(true)
	if _count_anim != null and _count_anim.has_animation(&"Increase"):
		_count_anim.play(&"Increase")
	return _count_anim


func _fit_count_badges(include_new: bool = false) -> void:
	var font: Font = _count_badge.get_theme_font(&"font")
	var clip: Control = _count_badge.get_parent()
	var available_width: float = clip.size.x - _count_badge.position.x
	var font_size: int = _count_font_size
	while font_size > 1:
		var width: float = (
			font.get_string_size(_count_badge.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		)
		if include_new and _count_badge_new != null:
			width = maxf(
				width,
				(
					font
					. get_string_size(
						_count_badge_new.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
					)
					. x
				)
			)
		if width <= available_width:
			break
		font_size -= 1
	_count_badge.add_theme_font_size_override(&"font_size", font_size)
	if _count_badge_new != null:
		_count_badge_new.add_theme_font_size_override(&"font_size", font_size)


func play_shake() -> void:
	if _count_anim == null or not _count_anim.has_animation(&"Shake"):
		return
	pivot_offset = size * 0.5
	_count_anim.play(&"Shake")


func set_red_dot(shown: bool) -> void:
	_red_dot.visible = shown


func _apply_self() -> void:
	apply_player_info(ProfileService.get_player_info())


func _frame_index(frame_id: int, form: int = 0) -> int:
	if frame_id == 0:
		return -1
	var i: int = ProfileCatalog.CLASSIC_FRAME_IDS.find(frame_id)
	if i >= 0:
		return i
	var j: int = ProfileCatalog.LEADERBOARD_FRAME_IDS.find(frame_id)
	if j >= 0:
		var f: int = form if ProfileCatalog.is_valid_form(form) else 0
		return (
			ProfileCatalog.CLASSIC_FRAME_IDS.size() + j * ProfileCatalog.FIRST_FRAME_FORM_COUNT + f
		)

	var k: int = ProfileCatalog.EVENT_FRAME_IDS.find(frame_id)
	if k >= 0:
		return (
			ProfileCatalog.CLASSIC_FRAME_IDS.size()
			+ ProfileCatalog.LEADERBOARD_FRAME_IDS.size() * ProfileCatalog.FIRST_FRAME_FORM_COUNT
			+ k
		)
	return -1


func _avatar_index(avatar_id: int) -> int:
	var i: int = ProfileCatalog.AVATAR_IDS.find(avatar_id)
	if i >= 0:
		return i
	var j: int = ProfileCatalog.EVENT_AVATAR_IDS.find(avatar_id)
	if j >= 0:
		return ProfileCatalog.AVATAR_IDS.size() + j
	return -1
