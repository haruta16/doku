## 色彩挑战按钮的文案和样式适配；把特殊关卡类型映射到开始与跳过按钮的外观。

extends RefCounted
class_name ColorChallengeBtnStyle

const _TEXT_KEY: String = "COLOR_CHALLENGE"

const _TEXT_FALLBACK: String = "Color Challenge"

const _SKIP_TEXT_KEY: String = "COLOR_CHALLENGE_SKIP"
const _SKIP_TEXT_FALLBACK: String = "Skip to Level %d"


static func apply(btn: Control, is_cc: bool) -> void:
	if btn == null:
		return
	if is_cc:
		btn.show_difficult = false

		btn.btn_icon = null
		btn.icon_at_left = false
		btn.btn_text = text()
	else:
		btn.btn_icon = null
		btn.icon_at_left = false


static func text() -> String:
	var translated: String = TranslationServer.translate(_TEXT_KEY)
	return _TEXT_FALLBACK if translated == _TEXT_KEY else translated


static func skip_text(target: int) -> String:
	var tpl: String = TranslationServer.translate(_SKIP_TEXT_KEY)
	if not tpl.contains("%d"):
		tpl = _SKIP_TEXT_FALLBACK
	return tpl % target
