## 金鱼关按钮的表现工具；设置金鱼图标、尺寸以及开始/跳过文案。

extends RefCounted
class_name GoldenFishBtnStyle

const ICON: Texture2D = preload("res://assets/sprites/game/fish_golden_btn.png")

const ICON_SIZE: Vector2 = Vector2(107, 110)

const ICON_GAP: float = 20.0

const _TEXT_KEY: String = "GOLDEN_FISH"

const _TEXT_FALLBACK: String = "Golden Fish"


static func apply(btn: Control, is_golden: bool) -> void:
	if btn == null:
		return
	if is_golden:
		btn.show_difficult = false
		btn.btn_icon = ICON
		btn.icon_size = ICON_SIZE
		btn.icon_gap = ICON_GAP
		btn.icon_at_left = true
		btn.btn_text = text()
	else:
		btn.btn_icon = null
		btn.icon_at_left = false


static func text() -> String:
	var t: String = TranslationServer.translate(_TEXT_KEY)
	return _TEXT_FALLBACK if t == _TEXT_KEY else t


const _SKIP_TEXT_KEY: String = "GOLDEN_FISH_SKIP"
const _SKIP_TEXT_FALLBACK: String = "Skip to Level %d"


static func skip_text(target: int) -> String:
	var tpl: String = TranslationServer.translate(_SKIP_TEXT_KEY)
	if not tpl.contains("%d"):
		tpl = _SKIP_TEXT_FALLBACK
	return tpl % target
