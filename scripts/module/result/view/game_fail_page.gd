class_name GameFailPage
extends UIFrameWindow

signal revive_requested

signal revive_ad_started

@onready var _title_label: CurveLabel = $Root/title/TitleLabel
@onready var _count_num: Label = $Root/Ctrl/CatCountRow/CountNum

@onready var _encourage_label: RichTextLabel = $Root/Ctrl/VBoxContainer/EncourageLabel
@onready var _revive_btn: Control = $Root/Ctrl/VBoxContainer/ReviveBtn
@onready var _restart_btn: Control = $Root/Ctrl/VBoxContainer/RestartBtn
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _revive_ad_icon: TextureRect = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/TextIconRow/Icon
@onready var _revive_badge: GameAdBadge = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/Badge

@onready
var _revive_text_icon_row: HBoxContainer = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/TextIconRow
@onready var _revive_main_label: Label = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/TextIconRow/Label
@onready var _revive_subtitle: Label = $Root/Ctrl/VBoxContainer/ReviveBtn/Root/SubtitleLabel

const _REVIVE_TWO_LINE_OFFSET: float = -20.0

const _REVIVE_ROW_MAX_WIDTH: float = 705.0
const _REVIVE_ROW_ICON_WIDTH: float = 100.0
const _REVIVE_ROW_SEPARATION: float = 24.0
const _REVIVE_MAIN_FONT_SIZE_BASE: int = 88
const _REVIVE_MAIN_FONT_SIZE_MIN: int = 40

var _revive_row_init_top: float = 0.0
var _revive_row_init_bottom: float = 0.0

var _level_config: Dictionary = {}
var _retry_params: Dictionary = {}

var _encourage_fade_tween: Tween = null


func _ready() -> void:
	_revive_row_init_top = _revive_text_icon_row.offset_top
	_revive_row_init_bottom = _revive_text_icon_row.offset_bottom
	_refresh_dynamic_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


func _refresh_dynamic_text() -> void:
	var key: String = (
		"FAIL_TITLE_FISH" if ABTestManager.life_icon.is_fish_life_bar() else "FAIL_TITLE"
	)
	_title_label.text = tr(key)

	var main_key: String = (
		"FAIL_REVIVE_3FISH" if ABTestManager.revive_life.is_alt_button_text() else "FAIL_REVIVE"
	)
	_revive_main_label.text = tr(main_key)
	var two_line: bool = ABTestManager.revive_life.is_two_line_button()
	_revive_subtitle.visible = two_line
	if two_line:
		_revive_text_icon_row.offset_top = _revive_row_init_top + _REVIVE_TWO_LINE_OFFSET
		_revive_text_icon_row.offset_bottom = _revive_row_init_bottom + _REVIVE_TWO_LINE_OFFSET
		_revive_subtitle.text = tr("FAIL_REVIVE_SUBTITLE_3FISH")
	else:
		_revive_text_icon_row.offset_top = _revive_row_init_top
		_revive_text_icon_row.offset_bottom = _revive_row_init_bottom
	_fit_main_label_width()


func _fit_main_label_width() -> void:
	if _revive_main_label == null:
		return

	_revive_main_label.add_theme_font_size_override("font_size", _REVIVE_MAIN_FONT_SIZE_BASE)
	var font: Font = _revive_main_label.get_theme_font("font")
	if font == null:
		return
	var icon_visible: bool = _revive_ad_icon != null and _revive_ad_icon.visible
	var avail: float = _REVIVE_ROW_MAX_WIDTH
	if icon_visible:
		avail -= _REVIVE_ROW_ICON_WIDTH + _REVIVE_ROW_SEPARATION
	var measured: float = (
		font
		. get_string_size(
			_revive_main_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _REVIVE_MAIN_FONT_SIZE_BASE
		)
		. x
	)
	if measured <= avail:
		return
	var new_size: int = maxi(
		_REVIVE_MAIN_FONT_SIZE_MIN, int(floor(_REVIVE_MAIN_FONT_SIZE_BASE * avail / measured))
	)
	_revive_main_label.add_theme_font_size_override("font_size", new_size)


func on_show(params: Dictionary = {}) -> void:
	SoundManager.set_bgm_paused(true)

	UIManager.block_input_briefly(self, 1.5)
	var lc: Dictionary = params.get("level_config", {})
	var rp: Dictionary = params.get("retry_params", {})
	var rc: int = params.get("remaining_cats", 0)
	show_fail(lc, rp, rc)


func on_hide() -> void:
	SoundManager.set_bgm_paused(false)
	_disconnect_self_reward_callbacks()
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	_anim.stop()
	_anim.play("disappear")
	await _anim.animation_finished

	_reset_fail_cat_spines()
	visible = false


func show_fail(
	level_config: Dictionary, retry_params: Dictionary = {}, remaining_cats: int = 0
) -> void:
	_level_config = level_config
	_retry_params = retry_params
	_count_num.text = str(remaining_cats)
	_refresh_dynamic_text()
	var pos: String = (
		Tracker.AdPos.DAILY_GAME_FAIL
		if _level_config.get("is_daily", false)
		else Tracker.AdPos.NORMAL_GAME_FAIL
	)

	var free: bool = _is_free_revive()
	_revive_btn.visible = true if free else UniKitManager.is_reward_valid("reward", pos)

	var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()
	if not free:
		if ad_tag:
			_revive_ad_icon.visible = false
			_revive_badge.visible = true
			_revive_badge.show_icon_with_ad()
			_revive_badge.scale = Vector2.ONE
		else:
			_revive_ad_icon.visible = true
			_revive_badge.visible = false
	else:
		_revive_ad_icon.visible = false
		_revive_badge.visible = true
		_revive_badge.show_free()
		_revive_badge.scale = Vector2.ONE * 1.4

	_fit_main_label_width()
	_refresh_encourage_label(remaining_cats)
	visible = true
	if ABTestManager.wrong_cat_effect.should_lower_fail_volume():
		SoundManager.play(SoundManager.Kind.LEVEL_FAIL_LOW)
	else:
		SoundManager.play(SoundManager.Kind.LEVEL_FAIL)

	var group1: bool = ABTestManager.life_icon.is_fish_life_bar()
	_anim.stop()

	_anim.play("RESET")
	_anim.advance(0.0)

	_reset_fail_cat_spines()
	_resume_fail_cat_spines()
	_anim.play("appear_group1" if group1 else "appear")

	_anim.advance(0.0)
	_anim.queue("idle_group1" if group1 else "idle")


func _reset_fail_cat_spines() -> void:
	for sp: SpineSprite in [$Root/SpineSprite, $Root/SpineSprite2]:
		if sp == null:
			continue
		sp.visible = true
		var st := sp.get_animation_state()
		if st != null:
			st.set_animation("in", false, 0)
			st.set_time_scale(0.0)
		sp.update_skeleton(0.0)
		sp.visible = false


func _resume_fail_cat_spines() -> void:
	for sp: SpineSprite in [$Root/SpineSprite, $Root/SpineSprite2]:
		if sp == null:
			continue
		var st := sp.get_animation_state()
		if st != null:
			st.set_time_scale(1.0)


func _is_free_revive() -> bool:
	if BaseGamePage.debug_force_free_tool == "all":
		return true
	if not ABTestManager.reward_unlock_level.is_reward_required_at(GameState.get_current_level()):
		return true
	return ABTestManager.revive_free_logic.should_free_revive()


func _refresh_encourage_label(remaining_cats: int) -> void:
	if _encourage_fade_tween != null and _encourage_fade_tween.is_valid():
		_encourage_fade_tween.kill()
	_encourage_fade_tween = null
	if not ABTestManager.fail_text.should_show_encourage():
		_encourage_label.visible = false
		return
	var level: int = int(_level_config.get("level", 1))
	var sz: int = int(_level_config.get("size", LevelData.get_size(level)))
	var delay: float
	var fade_dur: float
	if ABTestManager.fail_text.should_show_revive_promote() and _revive_btn.visible:
		var x: float = GameState.get_fail_text_revive_x(level)
		if x < 0.0:
			var is_daily: bool = _level_config.get("is_daily", false)
			x = FailTextStats.pick_revive_promote_x(level, sz, is_daily)
			GameState.set_fail_text_revive_x(level, x)
		_encourage_label.text = FailTextStats.format_revive_promote(x)
		delay = 0.8166
		fade_dur = 0.35
	else:
		var found_ratio: float = 0.0 if sz <= 0 else float(sz - remaining_cats) / float(sz)
		_encourage_label.text = FailTextStats.pick_encourage_text(found_ratio)
		delay = 0.9833
		fade_dur = 0.35

	_encourage_label.visible = true
	_encourage_label.modulate = Color(1, 1, 1, 0)
	_encourage_fade_tween = create_tween()
	_encourage_fade_tween.tween_interval(delay)
	_encourage_fade_tween.tween_property(_encourage_label, "modulate:a", 1.0, fade_dur)


func _on_revive_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.REVIVE, self)

	if _is_free_revive():
		ABTestManager.revive_free_logic.consume_if_needed()
		revive_ad_started.emit()
		revive_requested.emit()
		return

	var pos: String = (
		Tracker.AdPos.DAILY_GAME_FAIL
		if _level_config.get("is_daily", false)
		else Tracker.AdPos.NORMAL_GAME_FAIL
	)

	var show_id := UniKitManager.gen_show_id()
	if not UniKitManager.is_reward_ready("reward", pos, show_id):
		Toast.popup("AD_TOAST_NOT_READY", self)
		return

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != "reward":
			return
		revive_requested.emit()
	var on_closed := func(placement_id: String) -> void:
		if placement_id != "reward":
			return

	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)

	revive_ad_started.emit()
	UniKitManager.show_reward("reward", pos, show_id)


func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)


func _on_restart_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.RESTART, self)

	LevelOps.on_restart_click()
	if _level_config.get("is_daily", false):
		UIManager.show_ui(UiName.DAILY_GAME, {"_tracker_status": Tracker.GameStatus.RESTART})
		return

	var params: Dictionary = (
		_retry_params.duplicate()
		if not _retry_params.is_empty()
		else {"level_index": _level_config.get("level", 1)}
	)
	params["_tracker_status"] = Tracker.GameStatus.RESTART
	UIManager.show_ui(UiName.GAME, params)


func get_scr_name() -> String:
	return Tracker.Scr.NORMAL_GAME_FAIL
