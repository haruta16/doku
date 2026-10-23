## 排行活动开启提示；展示剩余时间，并在玩家确认后转入参加流程。

extends UIFrameWindow

@onready var _body_text: RichTextLabel = $Root/Content/DialogRoot/BodyText
@onready var _countdown_label: TabularDigitLabel = $Root/Content/DialogRoot/Banner/CountdownLabel
@onready var _countdown_icon: TextureRect = $Root/Content/DialogRoot/Banner/CountdownIcon

var _started: bool = false

@onready var _cd_icon_w: float = _countdown_icon.offset_right - _countdown_icon.offset_left
@onready var _cd_label_box_w: float = _countdown_label.offset_right - _countdown_label.offset_left
@onready
var _cd_group_center_x: float = (_countdown_icon.offset_left + _countdown_label.offset_right) * 0.5

const _CD_ICON_GAP: float = 13.0


func on_show(_params: Dictionary = {}) -> void:
	_started = false

	_body_text.text = tr("RANK_OPEN_DESC_FISH")

	_update_countdown()
	if not ClockTicker.second_tick.is_connected(_update_countdown):
		connect_managed(ClockTicker.second_tick, _update_countdown)

	if not _countdown_label.draw.is_connected(_reflow_countdown_row):
		connect_managed(_countdown_label.draw, _reflow_countdown_row)


func was_started() -> bool:
	return _started


func _update_countdown() -> void:
	_countdown_label.text = _format_hms(RankActivityManager.get_remaining_sec())
	_reflow_countdown_row()


func _reflow_countdown_row() -> void:
	if _cd_group_center_x <= 0.0:
		return

	var block_w: float = _countdown_label.ensure_block_width()

	if block_w <= 0.0:
		return
	var group_w: float = _cd_icon_w + _CD_ICON_GAP + block_w
	var group_right: float = _cd_group_center_x + group_w * 0.5
	var icon_left: float = group_right - group_w

	if is_equal_approx(_countdown_icon.offset_left, icon_left):
		return
	_countdown_icon.offset_left = icon_left
	_countdown_icon.offset_right = icon_left + _cd_icon_w
	_countdown_label.offset_right = group_right
	_countdown_label.offset_left = group_right - _cd_label_box_w


func _format_hms(sec: int) -> String:
	sec = maxi(0, sec)
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


func get_dlg_name() -> String:
	return Tracker.Dlg.CHALLENGE_GUIDE


func _on_action_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.PLAY, self)
	_started = true
	UIManager.hide_ui(UiName.RANK_ACTIVITY_OPEN_POPUP)


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	UIManager.hide_ui(_ui_name)
