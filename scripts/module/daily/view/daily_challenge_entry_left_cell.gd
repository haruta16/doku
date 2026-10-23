## 每日挑战左侧入口：同步日期状态与装扮猫头像，复用统一入口点击规则。
extends UIChildWindow

@onready var _text: Label = $Root/Label/Text
@onready var _cat_spine: SpineSprite = $Root/CatHead/CatSpine
@onready var _click_btn: Button = $ClickBtn


func on_create() -> void:
	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))

	visibility_changed.connect(_refresh_cat_head)


func on_show(_params: Dictionary = {}) -> void:
	connect_managed(ClockTicker.second_tick, _refresh)

	connect_managed(ProfileService.costume_changed, _refresh_cat_head)
	_refresh()


func _refresh() -> void:
	match DailyEntryState.compute_state():
		DailyEntryState.State.NORMAL:
			_text.text = DailyEntryState.countdown_text()
		DailyEntryState.State.LOCKED:
			_text.text = tr("DAILY_CHALLENGE_UNLOCK_AT") % DailyEntryState.UNLOCK_LEVEL
		DailyEntryState.State.DONE, DailyEntryState.State.REPLAY:
			_text.text = DailyEntryState.done_time_text()
	_refresh_cat_head()


func _refresh_cat_head() -> void:
	if _cat_spine == null:
		return
	var state: int = DailyEntryState.compute_state()
	_cat_spine.visible = (
		ABTestManager.dc_costume.has_costume() and state != DailyEntryState.State.LOCKED
	)
	if not _cat_spine.visible:
		return

	var costume_id: int = ProfileService.get_today_costume()
	DcEntryCatHead.apply(_cat_spine, costume_id, not ProfileService.is_costume_held(costume_id))


func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)
	VibrateManager.play_at(VibrateManager.Pos.DAILY_ENTRY_CLICK)

	DailyEntryState.handle_click(
		self,
		func() -> void:
			UIManager.show_ui(UiName.DAILY_GAME, {})
			UIManager.hide_ui(UiName.HOME),
		func() -> void:
			DcReplayFlow.open_confirm(
				self,
				func() -> void:
					UIManager.show_ui(UiName.DAILY_GAME, DcReplayFlow.enter_params())
					UIManager.hide_ui(UiName.HOME)
			)
	)
