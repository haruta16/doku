## 陪伴猫奖励展示页：演出宝箱与奖励内容，记录玩家是否领取并处理关闭流程。
extends UIFrameWindow

const System: GDScript = preload("res://scripts/module/home/core/home_companion_system.gd")
const Service: GDScript = preload("res://scripts/module/home/home_companion_service.gd")
const _AWARD_CELL: PackedScene = preload("res://scripts/module/award/ui/other/award_cell.tscn")
const _GIFT_CELL: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_gift_cell.tscn"
)

const _GIFT_CHEST_POINT: Vector2 = Vector2(565.0, 1301.0)

const _CHEST_REST_OFFSET: Vector2 = Vector2(25.0, 301.0)

const _CHEST_FLY_START: float = 0.067
const _CHEST_FLY_END: float = 0.35
const _CHEST_FROM_SCALE: float = 0.18
const _CHEST_SINK_START: float = 1.533
const _CHEST_SINK_END: float = 1.983
const _CHEST_SINK_DY: float = 200.0
const _CHEST_FADE_START: float = 2.0
const _CHEST_FADE_END: float = 2.3

const _REWARD_POP_START: float = 1.917
const _REWARD_POP_PEAK: float = 2.017
const _REWARD_POP_END: float = 2.284
const _REWARD_FADE_LEN: float = 0.05
const _REWARD_POP_FROM_SCALE: float = 0.5
const _REWARD_POP_PEAK_SCALE: float = 1.04
const _COLLECT_FADE_START: float = 2.3
const _COLLECT_FADE_END: float = 2.663

const _CLOSE_SWELL_LEN: float = 0.149
const _CLOSE_SHRINK_LEN: float = 0.168
const _CLOSE_SWELL_SCALE: float = 1.05
const _CLOSE_END_SCALE: float = 0.8
const _CLOSE_FADE_DELAY: float = 0.267
const _CLOSE_FADE_LEN: float = 0.05

const _DECOR_SPIN_DEG_PER_SEC: float = 12.0

const _TAG_WIDTH_TRIAL: float = 319.3
const _TAG_WIDTH_PERMANENT: float = 344.3
const _TAG_FONT_TRIAL: int = 64
const _TAG_FONT_PERMANENT: int = 50

const _ITEM_FRAME_SIZE: Vector2 = Vector2(278.0, 278.0)

const _ITEM_ICON_SIZE: Vector2 = Vector2(147.0, 147.0)

@export var halloween_cat_head: Texture2D

@export var tag_bg_trial: Texture2D

@export var tag_bg_permanent: Texture2D

var _reward_tier: int = -1
var _collected: bool = false

var _shown_at: int = 0
var _item_cell: Control = null
var _gift_cell: UIChildWindow = null
var _intro_tween: Tween = null
var _close_tween: Tween = null

var _intro_playing: bool = false

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _chest_layer: Control = $ChestLayer
@onready var _decor: TextureRect = $Content/Decor
@onready var _item_state: Control = $Content/ItemState
@onready var _skin_state: Control = $Content/SkinState
@onready var _cat_head: TextureRect = $Content/SkinState/CatHead
@onready var _tag: Control = $Content/SkinState/Info/Tag
@onready var _tag_center_x: float = (_tag.offset_left + _tag.offset_right) * 0.5
@onready var _tag_label: Label = $Content/SkinState/Info/Tag/TagLabel

@onready var _tag_bg: TextureRect = $Content/SkinState/Info/Tag/TagBg
@onready var _time_row: Control = $Content/SkinState/Info/TimeRow
@onready var _time_label: Label = $Content/SkinState/Info/TimeRow/TimeLabel
@onready var _avatar_state: Control = $Content/AvatarState
@onready var _avatar_cell: Control = $Content/AvatarState/AvatarCell
@onready var _collect_btn: Control = $Content/CollectBtn

const _AVATAR_CELL_SCALE: Vector2 = Vector2(2.162, 2.162)


func on_create() -> void:
	_avatar_cell.scale = _AVATAR_CELL_SCALE


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()


func on_show(params: Dictionary = {}) -> void:
	_reward_tier = int(params.get("reward_tier", -1))
	_collected = false
	_shown_at = ProfileService.costume_now()
	var kind: String = _reward_kind()
	_item_state.visible = kind == "mouse"

	_decor.visible = kind != "mouse"
	_skin_state.visible = kind == "trial_costume" or kind == "permanent_costume"
	_time_row.visible = kind == "trial_costume"
	_avatar_state.visible = kind == "avatar" or kind == "frame"
	match kind:
		"mouse":
			_show_item()
		"trial_costume", "permanent_costume":
			_cat_head.texture = (
				halloween_cat_head
				if halloween_cat_head != null
				else CostumeIcon.texture_for(CostumeCatalog.HALLOWEEN_COSTUME_ID)
			)
			_apply_tag_shape(kind == "trial_costume")
		"avatar":
			_avatar_cell.set_base_visible(true)
			_avatar_cell.set_base_texture_visible(false)
			_avatar_cell.set_avatar_visible(true)
			_avatar_cell.set_avatar(ProfileCatalog.HALLOWEEN_AVATAR_ID)
			_avatar_cell.set_frame_visible(false)
		"frame":
			_avatar_cell.set_base_visible(true)
			_avatar_cell.set_base_texture_visible(true)
			_avatar_cell.set_avatar_visible(false)
			_avatar_cell.set_frame_visible(true)
			_avatar_cell.set_frame(ProfileCatalog.HALLOWEEN_FRAME_ID)
		_:
			push_error("HomeCompanionRewardPage: 未知奖励档位 %d" % _reward_tier)
	_apply_texts()
	if _time_row.visible:
		_refresh_countdown()
		connect_managed(ClockTicker.second_tick, _refresh_countdown)
	add_update_listener(_spin_decor)
	_play_chest_intro(params.get("chest_from", Vector2.INF))


func was_collected() -> bool:
	return _collected


func on_hide() -> void:
	_stop_chest_intro()
	var shrink_nodes: Array[Control] = _intro_reward_nodes()
	if _decor.visible:
		shrink_nodes.append(_decor)
	_close_tween = create_tween().set_parallel(true)
	for node: Control in shrink_nodes:
		(
			_close_tween
			. tween_property(node, ^"scale", Vector2.ONE * _CLOSE_SWELL_SCALE, _CLOSE_SWELL_LEN)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_close_tween
			. tween_property(node, ^"scale", Vector2.ONE * _CLOSE_END_SCALE, _CLOSE_SHRINK_LEN)
			. set_delay(_CLOSE_SWELL_LEN)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN)
		)
		_close_tween.tween_property(node, ^"modulate:a", 0.0, _CLOSE_FADE_LEN).set_delay(
			_CLOSE_FADE_DELAY
		)
	_close_tween.tween_property(_collect_btn, ^"modulate:a", 0.0, _CLOSE_FADE_LEN).set_delay(
		_CLOSE_FADE_DELAY
	)
	await _close_tween.finished
	_close_tween = null


func _finish_close_tween() -> void:
	if _close_tween != null and _close_tween.is_running():
		_close_tween.custom_step(_CLOSE_SWELL_LEN + _CLOSE_SHRINK_LEN + _CLOSE_FADE_DELAY)
	_close_tween = null


func _play_chest_intro(chest_from: Variant) -> void:
	_finish_close_tween()
	_stop_chest_intro()
	var reward_nodes: Array[Control] = _intro_reward_nodes()
	for node: Control in reward_nodes:
		node.pivot_offset_ratio = Vector2(0.5, 0.5)
		node.scale = Vector2.ONE * _REWARD_POP_FROM_SCALE
		node.modulate.a = 0.0

	_decor.modulate.a = 0.0
	_collect_btn.modulate.a = 0.0
	_intro_playing = true

	var layer_origin: Vector2 = _chest_layer.get_global_rect().position
	var rest_point: Vector2 = (
		_chest_layer.get_global_rect().get_center() + _CHEST_REST_OFFSET - layer_origin
	)
	var start_point: Vector2 = rest_point
	if chest_from is Vector2 and (chest_from as Vector2).is_finite():
		start_point = (chest_from as Vector2) - layer_origin
	_gift_cell = create_child(_GIFT_CELL)
	if _gift_cell != null:
		_gift_cell.reparent(_chest_layer, false)
		_gift_cell.pivot_offset = _GIFT_CHEST_POINT
		_gift_cell.scale = Vector2.ONE * _CHEST_FROM_SCALE
		_gift_cell.position = start_point - _GIFT_CHEST_POINT
		_gift_cell.modulate.a = 1.0

	_intro_tween = create_tween().set_parallel(true)
	if _gift_cell != null:
		var fly_len: float = _CHEST_FLY_END - _CHEST_FLY_START
		(
			_intro_tween
			. tween_property(_gift_cell, ^"scale", Vector2.ONE, fly_len)
			. set_delay(_CHEST_FLY_START)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_intro_tween
			. tween_property(_gift_cell, ^"position", rest_point - _GIFT_CHEST_POINT, fly_len)
			. set_delay(_CHEST_FLY_START)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_intro_tween
			. tween_property(
				_gift_cell,
				^"position:y",
				rest_point.y - _GIFT_CHEST_POINT.y + _CHEST_SINK_DY,
				_CHEST_SINK_END - _CHEST_SINK_START
			)
			. set_delay(_CHEST_SINK_START)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			_intro_tween
			. tween_property(_gift_cell, ^"modulate:a", 0.0, _CHEST_FADE_END - _CHEST_FADE_START)
			. set_delay(_CHEST_FADE_START)
		)
	for node: Control in reward_nodes:
		_intro_tween.tween_property(node, ^"modulate:a", 1.0, _REWARD_FADE_LEN).set_delay(
			_REWARD_POP_START
		)
		(
			_intro_tween
			. tween_property(
				node,
				^"scale",
				Vector2.ONE * _REWARD_POP_PEAK_SCALE,
				_REWARD_POP_PEAK - _REWARD_POP_START
			)
			. set_delay(_REWARD_POP_START)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_intro_tween
			. tween_property(node, ^"scale", Vector2.ONE, _REWARD_POP_END - _REWARD_POP_PEAK)
			. set_delay(_REWARD_POP_PEAK)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
	(
		_intro_tween
		. tween_property(_decor, ^"modulate:a", 1.0, _REWARD_POP_END - _REWARD_POP_START)
		. set_delay(_REWARD_POP_START)
	)
	(
		_intro_tween
		. tween_property(_collect_btn, ^"modulate:a", 1.0, _COLLECT_FADE_END - _COLLECT_FADE_START)
		. set_delay(_COLLECT_FADE_START)
	)
	_intro_tween.finished.connect(_on_chest_intro_finished)


func _stop_chest_intro() -> void:
	if _intro_tween != null:
		_intro_tween.kill()
		_intro_tween = null
	_intro_playing = false
	var reward_nodes: Array[Control] = _intro_reward_nodes()
	for node: Control in reward_nodes:
		node.scale = Vector2.ONE
		node.modulate.a = 1.0
	_decor.scale = Vector2.ONE
	_decor.modulate.a = 1.0
	_collect_btn.modulate.a = 1.0
	if _gift_cell != null:
		destroy_child(_gift_cell)
		_gift_cell = null


func _on_chest_intro_finished() -> void:
	_intro_tween = null
	_stop_chest_intro()


func _intro_reward_nodes() -> Array[Control]:
	var nodes: Array[Control] = []
	var states: Array[Control] = [_item_state, _skin_state, _avatar_state]
	for node: Control in states:
		if node.visible:
			nodes.append(node)
	return nodes


func _reward_kind() -> String:
	if _reward_tier < 0 or _reward_tier >= System.REWARD_KINDS.size():
		return ""
	return System.REWARD_KINDS[_reward_tier]


func _show_item() -> void:
	if _item_cell == null:
		_item_cell = create_child(
			_AWARD_CELL,
			{
				"category": AwardItem.Category.TOOL,
				"kind": "mouse",
				"count": Service.MOUSE_REWARD_COUNT
			}
		)
		if _item_cell == null:
			return
		_item_cell.reparent(_item_state, false)
		_resize_around_center(_item_cell.get_node(^"Frame"), _ITEM_FRAME_SIZE)
	else:
		_item_cell.set_award("mouse", Service.MOUSE_REWARD_COUNT)

	_resize_around_center(_item_cell.get_node(^"IconImg"), _ITEM_ICON_SIZE)
	(_item_cell.get_node(^"CountTxt") as Label).text = "x%d" % Service.MOUSE_REWARD_COUNT


func _resize_around_center(target: Control, target_size: Vector2) -> void:
	var center: Vector2 = target.position + target.size * 0.5
	target.size = target_size
	target.position = center - target_size * 0.5


func _apply_tag_shape(is_trial: bool) -> void:
	var half_width: float = (_TAG_WIDTH_TRIAL if is_trial else _TAG_WIDTH_PERMANENT) * 0.5
	_tag.offset_left = _tag_center_x - half_width
	_tag.offset_right = _tag_center_x + half_width
	_tag_label.max_font_size = _TAG_FONT_TRIAL if is_trial else _TAG_FONT_PERMANENT
	_tag_bg.texture = tag_bg_trial if is_trial else tag_bg_permanent


func _apply_texts() -> void:
	var kind: String = _reward_kind()

	_tag_label.text = (
		tr("DC_COSTUME_TRIAL_TAG")
		if kind == "trial_costume"
		else tr("HOME_COMPANION_REWARD_PERMANENT_TAG")
	)
	_collect_btn.btn_text = tr("AD_REWARD_RESTORED_COLLECT")


func _refresh_countdown() -> void:
	var remaining: int = ProfileService.costume_trial_remaining_sec(
		CostumeCatalog.HALLOWEEN_COSTUME_ID
	)
	if remaining <= 0:
		remaining = maxi(
			0, CostumeCatalog.TRIAL_DURATION_SEC - (ProfileService.costume_now() - _shown_at)
		)

	@warning_ignore("integer_division")
	var minutes: int = (remaining + 59) / 60
	@warning_ignore("integer_division")
	_time_label.text = "%02d:%02d" % [minutes / 60, minutes % 60]


func _spin_decor() -> void:
	_decor.rotation_degrees = fmod(
		_decor.rotation_degrees + _DECOR_SPIN_DEG_PER_SEC * get_process_delta_time(), 360.0
	)


func get_dlg_name() -> String:
	return Tracker.Dlg.COMPANION_CAT_REWARD


func _on_collect_pressed() -> void:
	if _collected or _intro_playing or not is_showing():
		return
	_collected = true
	Tracker.track_btn_click(Tracker.Btn.COLLECT, self)
	UIManager.hide_ui(get_ui_name())


func _on_back_request() -> void:
	UIManager.hide_ui(get_ui_name())
