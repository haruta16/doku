## 道具按钮的广告角标：在广告、免费、开启和无网络状态间切换动画与宽度。
class_name GameAdBadge
extends Control

@onready var _ad_icon: TextureRect = $GreenRoot/Wrap/HBoxContainer/ADIcon
@onready var _ad_icon2: TextureRect = $GreenRoot/Wrap/HBoxContainer/ADIcon2
@onready var _ad_icon3: TextureRect = $GreenRoot/Wrap/HBoxContainer/ADIcon3
@onready var _no_net_icon: TextureRect = $GreenRoot/Wrap/HBoxContainer/NoNetIcon
@onready var _ad_tag: RichTextLabel = $GreenRoot/Wrap/HBoxContainer/ADTag
@onready var _root: PanelContainer = $GreenRoot
@onready var _anim: AnimationPlayer = $AnimationPlayer

const _NO_NET_BG_COLOR: Color = Color(0.4392157, 0.4392157, 0.4392157, 1)

const _ANIM_TO_NO_NET: StringName = &"NetworkChange1"
const _ANIM_TO_AD: StringName = &"NetworkChange2"

enum State { NONE, AD, ICON_WITH_AD, FREE, ON, NO_NETWORK }
var _state: int = State.NONE

var _style: StyleBoxFlat = null

var _bg_color_normal: Color = Color.WHITE


func _ready() -> void:
	_style = _root.get_theme_stylebox("panel") as StyleBoxFlat
	if _style != null:
		_bg_color_normal = _style.bg_color
	_assert_gray_matches_animation()
	show_ad()


func _assert_gray_matches_animation() -> void:
	if OS.has_feature("rel") or _anim == null:
		return
	if not _anim.has_animation(_ANIM_TO_NO_NET):
		push_error("GameAdBadge: 缺少动画 %s" % _ANIM_TO_NO_NET)
		return
	var anim: Animation = _anim.get_animation(_ANIM_TO_NO_NET)
	for track_idx in anim.get_track_count():
		if str(anim.track_get_path(track_idx)) != "GreenRoot:theme_override_styles/panel:bg_color":
			continue
		var key_count: int = anim.track_get_key_count(track_idx)
		if key_count == 0:
			continue
		var last_color: Color = anim.track_get_key_value(track_idx, key_count - 1)
		if not last_color.is_equal_approx(_NO_NET_BG_COLOR):
			push_error(
				(
					"GameAdBadge: 灰底两处不一致 —— 常量=%s 动画末帧=%s(改一处必改另一处)"
					% [str(_NO_NET_BG_COLOR), str(last_color)]
				)
			)
		return


func _reset_all() -> void:
	if _anim != null and _anim.is_playing():
		_anim.stop()
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = false
	_no_net_icon.visible = false
	_ad_tag.visible = false
	_root.scale = Vector2.ONE
	_root.modulate = Color.WHITE
	if _style != null:
		_style.bg_color = _bg_color_normal


func _pin_pill_width() -> void:
	if _root == null:
		return
	_root.custom_minimum_size.x = 0.0
	_root.custom_minimum_size.x = _root.get_combined_minimum_size().x


func _release_pill_width() -> void:
	if _root == null:
		return
	_root.custom_minimum_size.x = 0.0


func show_ad(animated: bool = false) -> void:
	if _state == State.AD:
		return
	var from_no_net: bool = _state == State.NO_NETWORK
	_state = State.AD

	call_deferred("_release_pill_width")
	if animated and from_no_net and _play_switch(_ANIM_TO_AD):
		return
	_reset_all()
	_ad_icon.visible = true


func show_icon_with_ad() -> void:
	if _state == State.ICON_WITH_AD:
		return
	_state = State.ICON_WITH_AD
	_reset_all()
	_ad_icon2.visible = true
	_ad_tag.text = "AD"
	_ad_tag.visible = true

	call_deferred("_pin_pill_width")


func show_free() -> void:
	if _state == State.FREE:
		return
	_state = State.FREE
	_reset_all()
	_ad_tag.visible = true
	_ad_tag.text = "Free"
	call_deferred("_pin_pill_width")


func show_on() -> void:
	if _state == State.ON:
		return
	_state = State.ON
	_reset_all()
	_ad_tag.visible = true
	_ad_tag.text = "ON"
	call_deferred("_pin_pill_width")


func show_no_network(animated: bool = false) -> void:
	if _state == State.NO_NETWORK:
		return
	var from_ad: bool = _state == State.AD
	_state = State.NO_NETWORK

	call_deferred("_release_pill_width")
	if animated and from_ad and _play_switch(_ANIM_TO_NO_NET):
		return
	_reset_all()
	_no_net_icon.visible = true
	if _style != null:
		_style.bg_color = _NO_NET_BG_COLOR


func _play_switch(anim_name: StringName) -> bool:
	if _anim == null or not _anim.has_animation(anim_name):
		return false
	_anim.play(anim_name)
	return true
