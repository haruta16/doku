extends UIChildWindow

@onready var _state_normal: Control = $DcEntryImg/StateNormal
@onready var _state_locked: Control = $DcEntryImg/StateLocked
@onready var _state_done: Control = $DcEntryImg/StateDone
@onready var _normal_date: Label = $DcEntryImg/StateNormal/Jun3Txt
@onready var _normal_time: Label = $DcEntryImg/StateNormal/CountdownGroup/Countdown/TimeTxt
@onready var _done_date: Label = $DcEntryImg/StateDone/Jun3Txt
@onready var _done_time: Label = $DcEntryImg/StateDone/CountdownGroup/Countdown/TimeTxt
@onready var _done_rank: Label = $DcEntryImg/StateDone/ActionBtn/TOP90Txt
@onready var _unlock_label: Label = $DcEntryImg/StateLocked/LockGroup/UnlockAtLv21Txt
@onready var _click_btn: Button = $ClickBtn


func on_create() -> void:
	create_tick(1.0, _refresh)

	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


func on_show(_params: Dictionary = {}) -> void:
	_refresh()


func _refresh() -> void:
	var s: int = DailyEntryState.compute_state()
	_state_normal.visible = s == DailyEntryState.State.NORMAL
	_state_locked.visible = s == DailyEntryState.State.LOCKED
	_state_done.visible = s == DailyEntryState.State.DONE
	match s:
		DailyEntryState.State.NORMAL:
			_normal_date.text = DailyEntryState.today_date_text()
			_normal_time.text = DailyEntryState.countdown_text()
		DailyEntryState.State.LOCKED:
			_unlock_label.text = tr("DAILY_CHALLENGE_UNLOCK_AT") % DailyEntryState.UNLOCK_LEVEL
		DailyEntryState.State.DONE:
			_done_date.text = DailyEntryState.today_date_text()
			_done_time.text = DailyEntryState.done_time_text()
			_done_rank.text = DailyEntryState.done_rank_text()


func _on_click_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)

	DailyEntryState.handle_click(self)
