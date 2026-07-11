class_name DailyAutoMarkPopup
extends UIFrameWindow

const _AD_POS: String = Tracker.AdPos.AUTOX_REWARD

@onready var _primary_btn: Button = $Root/Content/Label/VBoxContainer/DualBtnArea/PrimaryBtn
@onready var _secondary_btn: Button = $Root/Content/Label/VBoxContainer/DualBtnArea/SecondaryBtn
@onready
var _primary_badge: GameAdBadge = $Root/Content/Label/VBoxContainer/DualBtnArea/PrimaryBtn/Badge
@onready
var _ad_icon_box: Control = $Root/Content/Label/VBoxContainer/DualBtnArea/PrimaryBtn/BtnGroup/AdIconBox
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer
@onready var _label: Control = $Root/Content/Label
@onready var _cat_popup: Control = $Root/Content/CatPopup
@onready
var _best_record_top_txt: RichTextLabel = $Root/Content/Label/VBoxContainer/LabelArea/BestRecordTopTxt
@onready var _almost_there: Control = $Root/Content/Label/VBoxContainer/LabelArea/AlmostThere

const _ALMOST_THERE_TOP_WITH_BEST: float = 211.0
const _ALMOST_THERE_BOTTOM_WITH_BEST: float = 361.0
const _ALMOST_THERE_TOP_NO_BEST: float = 130.0
const _ALMOST_THERE_BOTTOM_NO_BEST: float = 280.0

const _CAT_OVERHANG_ABOVE_LABEL: float = 339.0
const _CAT_OVERLAP_INTO_LABEL: float = 68.0

var _closing: bool = false

var _ad_requested: bool = false

var _is_free_mode: bool = false


func _ready() -> void:
	bind_press_release_scale(_primary_btn)
	bind_press_release_scale(_secondary_btn)

	_label.resized.connect(_sync_cat_to_label)


func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	_ad_requested = false
	_is_free_mode = not GameState.is_daily_auto_mark_free_consumed()
	_apply_mode_visibility()
	_apply_best_record_visibility()
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")
	_anim.advance(0.0)


func on_hide() -> void:
	if _closing:
		return
	_closing = true
	_disconnect_self_reward_callbacks()
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.DAILY_AUTO_MARK_POPUP


func _apply_mode_visibility() -> void:
	if _is_free_mode:
		_ad_icon_box.visible = false
		_primary_badge.visible = true
		_primary_badge.show_free()
		_primary_badge.scale = Vector2.ONE * 1.4
		_secondary_btn.visible = false
	else:
		var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()
		if ad_tag:
			_ad_icon_box.visible = false
			_primary_badge.visible = true
			_primary_badge.show_icon_with_ad()
			_primary_badge.scale = Vector2.ONE
		else:
			_ad_icon_box.visible = true
			_primary_badge.visible = false
		_secondary_btn.visible = true


func _apply_best_record_visibility() -> void:
	var best: float = GameState.get_daily_best_beat_percent()
	if best <= 0.0:
		_best_record_top_txt.visible = false
		_almost_there.offset_top = _ALMOST_THERE_TOP_NO_BEST
		_almost_there.offset_bottom = _ALMOST_THERE_BOTTOM_NO_BEST
		return
	_best_record_top_txt.visible = true
	_almost_there.offset_top = _ALMOST_THERE_TOP_WITH_BEST
	_almost_there.offset_bottom = _ALMOST_THERE_BOTTOM_WITH_BEST
	var top_pct: float = 100.0 - best
	var pct_text: String = I18nFormat.percent(top_pct, 1)
	_best_record_top_txt.text = ""
	_best_record_top_txt.append_text(tr("DAILY_AUTO_MARK_BEST_RECORD") % pct_text)


func _on_primary_btn_pressed() -> void:
	if _closing:
		return
	if _is_free_mode:
		_consume_free_and_activate()
		return
	if _ad_requested:
		return

	var show_id := UniKitManager.gen_show_id()
	if not UniKitManager.is_reward_ready("reward", _AD_POS, show_id):
		Toast.popup("AD_TOAST_NOT_READY", self)
		return
	_ad_requested = true

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != "reward":
			return
		GameState.mark_daily_auto_mark_enabled_today()

		Tracker.track_prop_get(Tracker.Prop.AUTOX, Tracker.PropSource.AUTOX_REWARD_AD, 1, 0)
		Tracker.track_prop_use(Tracker.Prop.AUTOX, Tracker.Scr.DAILY_GAME, 1, 0)
		if not _closing:
			UIManager.hide_ui(get_ui_name())
	var on_closed := func(placement_id: String) -> void:
		if placement_id != "reward":
			return

		if not _closing:
			UIManager.hide_ui(get_ui_name())
	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)
	UniKitManager.show_reward("reward", _AD_POS, show_id)


func _on_secondary_btn_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


func _consume_free_and_activate() -> void:
	GameState.mark_daily_auto_mark_free_consumed()
	GameState.mark_daily_auto_mark_enabled_today()
	UIManager.hide_ui(get_ui_name())


func _sync_cat_to_label() -> void:
	if not is_instance_valid(_label) or not is_instance_valid(_cat_popup):
		return
	var label_top_y: float = _label.position.y
	var anchor_ref_y: float = _cat_popup.get_parent().size.y * _cat_popup.anchor_top
	_cat_popup.offset_top = label_top_y - _CAT_OVERHANG_ABOVE_LABEL - anchor_ref_y
	_cat_popup.offset_bottom = label_top_y + _CAT_OVERLAP_INTO_LABEL - anchor_ref_y


func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.get("callable", Callable())
		if cb.is_valid() and cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.get("callable", Callable())
		if cb.is_valid() and cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)
