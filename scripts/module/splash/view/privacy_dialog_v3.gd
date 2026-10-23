## 第三版隐私确认页：以另一套界面表现同一隐私接受流程。
extends UIFrameWindow

signal accepted

@onready
var _content_label: RichTextLabel = $Root/Content/CenterBox/PopupFrame/Bg/BgVBox/PopUpTextTxt
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

var _closing: bool = false


func _ready() -> void:
	var terms_url: String = UniKitManager.get_localized_privacy_url(
		"https://oakevergames.com/tos.html"
	)
	var policy_url: String = UniKitManager.get_localized_privacy_url(
		"https://oakevergames.com/pp.html"
	)
	var desc_text: String = tr("PRIVACY_DIALOG_DESC_RICH") % [terms_url, policy_url]
	_content_label.text = desc_text.replace("#489C52", "#4176D2")
	_content_label.meta_clicked.connect(_on_link_clicked)


func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")


func _on_accept_btn_pressed() -> void:
	if _closing:
		return
	Tracker.track_btn_click(Tracker.Btn.ACCEPT, self)
	_closing = true
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished
	accepted.emit()

	visible = false


func _on_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


func get_dlg_name() -> String:
	return Tracker.Dlg.PRIVACY
