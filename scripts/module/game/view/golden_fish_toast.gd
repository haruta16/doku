## 金鱼玩法提示卡：选择对应卡片变体，并把玩法参数转为开局副标题。
class_name GoldenFishToast
extends BaseGameToast

const APPEAR_ANIM: StringName = &"Beginning"

const _SUBTITLE_KEY: String = "GOLDEN_FISH_CHALLENGE_MODE"
const _SUBTITLE_FALLBACK: String = "Challenge Mode"

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
		_title_label.text = GoldenFishBtnStyle.text()
	if _label != null:
		_label.text = TextHighlightRenderer.render(
			ABTestManager.text_highlight, _SUBTITLE_KEY, subtitle_text(), "#FFEE00"
		)


static func subtitle_text() -> String:
	var t: String = TranslationServer.translate(_SUBTITLE_KEY)
	return _SUBTITLE_FALLBACK if t == _SUBTITLE_KEY else t
