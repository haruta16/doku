## 每日挑战重玩确认页：保存确认和关闭回调，保证同一轮展示只消费一次选择。
class_name DcReplayConfirmPage
extends UIFrameWindow

@onready var _title_label: Label = $Root/Content/DialogRoot/TitleLabel
@onready var _content_text: RichTextLabel = $Root/Content/DialogRoot/ContentText
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _on_confirm: Callable
var _on_close: Callable

var _consumed: bool = false


func on_show(params: Dictionary = {}) -> void:
	_consumed = false
	_title_label.text = tr(params.get("title", _title_label.text))

	_content_text.text = str(params.get("content", _content_text.text))
	_on_confirm = params.get("on_confirm", Callable())
	_on_close = params.get("on_close", Callable())


func on_hide() -> void:
	_anim.play_section_with_markers(&"GenericPopup", &"Mark", &"")
	await _anim.animation_finished


func get_dlg_name() -> String:
	return Tracker.Dlg.DC_REPLAY


func _on_replay_btn_pressed() -> void:
	if _consumed:
		return
	_consumed = true

	Tracker.track_btn_click(Tracker.Btn.REPLAY, self)
	UIManager.hide_ui(_ui_name)
	if _on_confirm.is_valid():
		_on_confirm.call()


func _on_close_btn_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	UIManager.hide_ui(_ui_name)
	if _on_close.is_valid():
		_on_close.call()


func _on_back_request() -> void:
	_on_close_btn_pressed()
