## 实验文案高亮：解析 [tag] 标记，按配置固定高亮或为每个文案键缓存本次会话的随机选择。
extends RefCounted
class_name TextHighlightRenderer

const _OPEN_TAG: String = "[tag]"
const _CLOSE_TAG: String = "[/tag]"
const _KEY_SUFFIX: String = "_HIGH_LIGHT"

static var _session_choices: Dictionary = {}


static func render(
	config: TextHighlightConfig, text_key: String, source: String, hex_color: String
) -> String:
	var mode: int = TextHighlightConfig.VALUE_CONTROL
	if config != null and config.should_always_highlight():
		mode = TextHighlightConfig.VALUE_ALWAYS
	elif config != null and config.should_randomize_per_key():
		mode = TextHighlightConfig.VALUE_SESSION_RANDOM
	return render_for_mode(mode, text_key, source, hex_color)


static func render_for_mode(
	mode: int, text_key: String, source: String, hex_color: String
) -> String:
	var should_highlight: bool = false
	var choice_action: String = ""
	match mode:
		TextHighlightConfig.VALUE_ALWAYS:
			should_highlight = true
		TextHighlightConfig.VALUE_SESSION_RANDOM:
			if _session_choices.has(text_key):
				should_highlight = bool(_session_choices[text_key])
				choice_action = "复用已有结果"
			else:
				should_highlight = randi_range(0, 1) == 1
				_session_choices[text_key] = should_highlight
				choice_action = "首次随机"
	var use_key: String = text_key
	var result: String = source
	if should_highlight:
		var highlighted_key: String = text_key + _KEY_SUFFIX
		var highlighted: String = TranslationServer.translate(highlighted_key)
		if highlighted != highlighted_key:
			use_key = highlighted_key
			result = _color_paired_tags(highlighted, hex_color)
	if mode == TextHighlightConfig.VALUE_SESSION_RANDOM:
		print(
			(
				"[TextHighlight] group=%d action=%s key=%s highlight=%s use_key=%s"
				% [mode, choice_action, text_key, str(should_highlight), use_key]
			)
		)
	return result


static func _color_paired_tags(source: String, hex_color: String) -> String:
	var result: String = ""
	var cursor: int = 0
	while cursor < source.length():
		var opening: int = source.find(_OPEN_TAG, cursor)
		if opening < 0:
			result += source.substr(cursor).replace(_CLOSE_TAG, "")
			break
		result += source.substr(cursor, opening - cursor).replace(_CLOSE_TAG, "")
		var content_start: int = opening + _OPEN_TAG.length()
		var closing: int = source.find(_CLOSE_TAG, content_start)
		if closing < 0:
			result += source.substr(content_start).replace(_OPEN_TAG, "").replace(_CLOSE_TAG, "")
			break
		var content: String = source.substr(content_start, closing - content_start)
		result += "[color=%s]%s[/color]" % [hex_color, content.replace(_OPEN_TAG, "")]
		cursor = closing + _CLOSE_TAG.length()
	return result
