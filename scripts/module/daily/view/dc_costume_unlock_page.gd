## 每日装扮解锁页：展示本日装扮与成绩，发布装备选择并刷新剩余时间。
class_name DcCostumeUnlockPage
extends UIFrameWindow

signal choice_made(equipped: bool)

const _IDLE_ANIM: String = "idle"

const _DEFAULT_BEAT_PERCENT: float = 50.0

const _BEAT_DECIMALS: int = 1

const _PCT_COLOR_HEX: String = "02BE52"

const _PCT_FONT_SIZE: int = 80

const _DECOR_SPIN_DEG_PER_SEC: float = 12.0

var _busy: bool = false

var _costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID

var _beat_percent: float = _DEFAULT_BEAT_PERCENT

var _spine: SpineSprite = null

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _headline: RichTextLabel = $Content/HeadlineLabel
@onready var _decor: TextureRect = $Content/CatGroup/Decor
@onready var _tag_label: Label = $Content/CatGroup/Cat/Info/TrialTag/TagLabel
@onready var _cat_icon: TextureRect = $Content/CatGroup/Cat/CatIcon
@onready var _cat_anchor: Node2D = $Content/CatGroup/Cat/CatAnchor
@onready var _time_label: Label = $Content/CatGroup/Cat/Info/TimeRow/TimeLabel


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_headline_text()
		_apply_tag_text()


func on_show(params: Dictionary = {}) -> void:
	_busy = false
	_costume_id = int(params.get("costume_id", ProfileService.get_today_costume()))
	_beat_percent = float(params.get("beat_percent", _DEFAULT_BEAT_PERCENT))
	_apply_headline_text()
	_apply_tag_text()
	_apply_costume_look()
	_refresh_countdown()
	connect_managed(ClockTicker.second_tick, _refresh_countdown)

	add_update_listener(_spin_decor)


func on_hide() -> void:
	_anim.play_section_with_markers(&"GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func _apply_headline_text() -> void:
	if _headline == null:
		return
	var pct_markup: String = (
		"[color=#%s][font_size=%d]%s[/font_size][/color]"
		% [_PCT_COLOR_HEX, _PCT_FONT_SIZE, I18nFormat.percent(_beat_percent, _BEAT_DECIMALS)]
	)
	var template: String = tr("DAILY_WIN_BEAT")
	var desc: String = ""
	if template.contains("%s"):
		desc = template % pct_markup
	else:
		desc = template + " " + pct_markup
	_headline.text = "%s %s" % [tr("DC_COSTUME_UNLOCK_TITLE"), desc]


func _apply_tag_text() -> void:
	if _tag_label == null:
		return
	_tag_label.text = tr("DC_COSTUME_TRIAL_TAG")


func _apply_costume_look() -> void:
	if _cat_icon == null:
		return
	var tex: Texture2D = CostumeIcon.texture_for(_costume_id)
	_cat_icon.visible = tex != null
	_cat_icon.texture = tex
	if tex != null:
		if _spine != null:
			_spine.visible = false
		return
	_ensure_spine()
	_spine.visible = true
	CostumeSkin.apply(_spine, _costume_id)
	_freeze_spine_idle()


func _ensure_spine() -> void:
	if _spine != null:
		return
	_spine = SpineSprite.new()
	_spine.skeleton_data_res = CostumeSkin.SKELETON_RES
	_cat_anchor.add_child(_spine)


func _freeze_spine_idle() -> void:
	var data: SpineSkeletonDataResource = _spine.get_skeleton_data_res()
	if data == null or data.find_animation(_IDLE_ANIM) == null:
		return
	var state: SpineAnimationState = _spine.get_animation_state()
	if state == null:
		return
	state.set_animation(_IDLE_ANIM, false, 0)
	state.set_time_scale(0.0)


func _spin_decor() -> void:
	if _decor == null:
		return
	_decor.rotation_degrees = fmod(
		_decor.rotation_degrees + _DECOR_SPIN_DEG_PER_SEC * get_process_delta_time(), 360.0
	)


func _refresh_countdown() -> void:
	if _time_label == null:
		return
	_time_label.text = _format_hm(ProfileService.costume_trial_remaining_sec(_costume_id))


static func _format_hm(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)

	@warning_ignore("integer_division")
	var total_minutes: int = (sec + 59) / 60
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


func get_dlg_name() -> String:
	return Tracker.Dlg.DC_TRIAL_SKIN


func _on_equip_pressed() -> void:
	if _busy:
		return
	_busy = true
	Tracker.track_btn_click(Tracker.Btn.EQUIP, self)

	if not ProfileService.set_costume_id(_costume_id):
		push_error("DcCostumeUnlockPage: equip rejected, costume_id=%d not held" % _costume_id)
	choice_made.emit(true)
	UIManager.hide_ui(_ui_name)


func _on_later_pressed() -> void:
	if _busy:
		return
	_busy = true
	Tracker.track_btn_click(Tracker.Btn.LATER, self)
	choice_made.emit(false)
	UIManager.hide_ui(_ui_name)


func _on_back_request() -> void:
	_on_later_pressed()
