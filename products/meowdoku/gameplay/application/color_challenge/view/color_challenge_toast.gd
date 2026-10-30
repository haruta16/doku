## 色彩挑战的开局提示；选择对应样式卡片并设置本地化标题、副标题及长文案字号。

class_name ColorChallengeToast
extends BaseGameToast

const APPEAR_ANIM: StringName = &"Beginning"

const _TITLE_KEY: String = "COLOR_CHALLENGE"
const _TITLE_FALLBACK: String = "Color Challenge"

const _SUBTITLE_KEY: String = "COLOR_CHALLENGE_TOAST_DESC"
const _SUBTITLE_FALLBACK: String = "Hard to tell cells!"

@onready
var _title_label: Label = $Root/Card/CardGolden/PanelContainer/VBoxContainer/HBoxContainer/TitleLabel


func _appear_anim() -> StringName:
	return APPEAR_ANIM


func _dlg_name() -> String:
	return Tracker.Dlg.GOLDEN_FISH_TOAST


func _select_variant_card() -> void:
	_label = (
		_card.get_node_or_null("CardGolden/PanelContainer/VBoxContainer/Label") as RichTextLabel
	)


func _label_subpaths() -> Dictionary:
	return {}


func _apply_text(_params: Dictionary) -> void:
	if _title_label != null:
		_title_label.text = title_text()
	if _label != null:
		_label.text = subtitle_text()


func _maybe_shrink_card7_font() -> void:
	pass


static func title_text() -> String:
	var translated: String = TranslationServer.translate(_TITLE_KEY)
	return _TITLE_FALLBACK if translated == _TITLE_KEY else translated


static func subtitle_text() -> String:
	var translated: String = TranslationServer.translate(_SUBTITLE_KEY)
	return _SUBTITLE_FALLBACK if translated == _SUBTITLE_KEY else translated
