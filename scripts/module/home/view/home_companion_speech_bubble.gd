## 陪伴猫对白气泡：根据文本布局变化延迟重算尺寸，保持气泡包住文字。
extends Control

const TEXT_PADDING: Vector2 = Vector2(40.0, 20.0)

@export var text_label: Label
@export var max_width: float = 808.0

var _available_width: float = 808.0
var _fit_queued: bool = false


func _ready() -> void:
	fit_to_text(max_width)


func fit_to_text(available_width: float) -> void:
	_available_width = available_width
	var width_limit: float = maxf(TEXT_PADDING.x * 2.0 + 1.0, minf(max_width, available_width))
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY
	var language: String = (
		text_label.language
		if not text_label.language.is_empty()
		else TranslationServer.get_locale()
	)
	var content: String = text_label.tr(text_label.text)
	if text_label.uppercase:
		content = TextServerManager.get_primary_interface().string_to_upper(content, language)
	paragraph.add_string(
		content,
		text_label.get_theme_font("font"),
		text_label.get_theme_font_size("font_size"),
		language
	)
	size.x = minf(width_limit, maxf(180.0, ceilf(paragraph.get_size().x) + TEXT_PADDING.x * 2.0))

	size.y = ceilf(text_label.get_minimum_size().y) + TEXT_PADDING.y * 2.0

	text_label.update_minimum_size()
	text_label.set_size(Vector2(size.x - TEXT_PADDING.x * 2.0, size.y - TEXT_PADDING.y * 2.0))
	text_label.set_position(TEXT_PADDING)


func _on_text_layout_changed() -> void:
	if not is_node_ready() or _fit_queued:
		return
	_fit_queued = true
	_refit.call_deferred()


func _refit() -> void:
	_fit_queued = false
	fit_to_text(_available_width)
