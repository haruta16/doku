## 第一组通关统计面板：格式化时间、分数与百分比强调，入场完成后启用继续按钮。
class_name PassPageG1Board
extends Control

signal next_pressed

@onready var _title: Label = $ContentGroup/Popup/TitleLabel
@onready var _size_value: Label = $ContentGroup/Popup/StatsPanel/StatRow2/Cells/ValueLabel
@onready var _time_value: Label = $ContentGroup/Popup/StatsPanel/StatRow3/Cells/ValueLabel
@onready var _score_value: Label = $ContentGroup/Popup/StatsPanel/StatRow4/Cells/ValueLabel
@onready var _combo_value: Label = $ContentGroup/Popup/StatsPanel/StatRow5/Cells/ValueLabel
@onready var _size_key: Label = $ContentGroup/Popup/StatsPanel/StatRow2/Cells/KeyLabel
@onready var _time_key: Label = $ContentGroup/Popup/StatsPanel/StatRow3/Cells/KeyLabel
@onready var _score_key: Label = $ContentGroup/Popup/StatsPanel/StatRow4/Cells/KeyLabel
@onready var _combo_key: Label = $ContentGroup/Popup/StatsPanel/StatRow5/Cells/KeyLabel
@onready var _praise: RichTextLabel = $ContentGroup/PraiseLabel
@onready var _next_btn: Control = $ContentGroup/CtaRow/NextBtn
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _sprite2d: Sprite2D = $ContentGroup/Sprite2D
@onready var _popup: Control = $ContentGroup/Popup

var _sprite2d_y_offset_from_popup: float = 65.0

var _next_enabled: bool = true

var _appear_seq: int = 0

const _PRAISE_MAX_HEIGHT: float = 200.0
const _PRAISE_BASE_FONT_SIZE: int = 76
const _PRAISE_MIN_FONT_SIZE: int = 40
const _PRAISE_FONT_STEP: int = 2

const _NEXT_BTN_MARKER: StringName = &"button_show"


func _ready() -> void:
	_apply_stat_key_labels()
	if _next_btn != null and _next_btn.has_signal("tag_pressed"):
		_next_btn.tag_pressed.connect(_on_next_tag_pressed)

	_sync_sprite2d_to_popup()
	_popup.item_rect_changed.connect(_sync_sprite2d_to_popup)


func _apply_stat_key_labels() -> void:
	_size_key.text = tr("PASS_PAGE_SIZE")
	_time_key.text = tr("PASS_PAGE_TIME")
	_score_key.text = tr("PASS_PAGE_SCORE")
	_combo_key.text = tr("PASS_PAGE_COMBO")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_stat_key_labels()


func _sync_sprite2d_to_popup() -> void:
	_sprite2d.position.y = _popup.position.y + _sprite2d_y_offset_from_popup


func _on_next_tag_pressed() -> void:
	if _next_enabled:
		next_pressed.emit()


func populate(
	title_text: String,
	praise_bbcode: String,
	next_label: String,
	next_is_hard: bool,
	stats: Dictionary,
	is_next_golden: bool = false
) -> void:
	_title.text = title_text
	if praise_bbcode.is_empty():
		_praise.visible = false
	else:
		_praise.visible = true
		_praise.text = _apply_pass_page_highlight(praise_bbcode)
		_fit_praise_font_size()
	if "btn_text" in _next_btn:
		_next_btn.btn_text = next_label
	if "show_difficult" in _next_btn:
		_next_btn.show_difficult = next_is_hard
	if "hard_effect_variant" in _next_btn:
		_next_btn.hard_effect_variant = ABTestManager.hard_button.effect_variant()

	if "btn_icon" in _next_btn:
		GoldenFishBtnStyle.apply(_next_btn, is_next_golden)
	var sz: int = int(stats.get("size", 0))
	_size_value.text = "%d×%d" % [sz, sz]

	_time_value.text = _format_time(ceili(float(stats.get("elapsed_sec", 0.0))))
	_score_value.text = _format_score(int(stats.get("final_score", 0)))
	_combo_value.text = "%d" % int(stats.get("max_combo", 0))


func set_next_super_hard(is_super_hard: bool) -> void:
	if "super_hard" in _next_btn:
		_next_btn.super_hard = is_super_hard


func _apply_pass_page_highlight(bbcode: String) -> String:
	var s: String = _normalize_percent_highlight(bbcode)
	s = _highlight_leading_digits(s)
	s = _highlight_free_percentages(s)
	return s


func _normalize_percent_highlight(bbcode: String) -> String:
	var s: String = bbcode.replace("[font_size=90][b][color=#02BE52]", "[color=#F19320]")
	s = s.replace("[/color][/b][/font_size]", "[/color]")
	return s


func _highlight_leading_digits(bbcode: String) -> String:
	var prefix: String = ""
	var body: String = bbcode
	if body.begins_with("[center]"):
		prefix = "[center]"
		body = body.substr(prefix.length())
	var i: int = 0
	while i < body.length() and body[i] >= "0" and body[i] <= "9":
		i += 1
	if i == 0:
		return bbcode
	var digits: String = body.substr(0, i)
	var rest: String = body.substr(i)
	return "%s[color=#F19320]%s[/color]%s" % [prefix, digits, rest]


func _highlight_free_percentages(bbcode: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("\\d+(?:\\.\\d+)?%")
	var matches: Array = re.search_all(bbcode)
	if matches.is_empty():
		return bbcode

	var wrapped: Array = []
	var scan: int = 0
	while true:
		var op_start: int = bbcode.find("[color=", scan)
		if op_start == -1:
			break
		var op_end: int = bbcode.find("]", op_start)
		if op_end == -1:
			break
		var cl_start: int = bbcode.find("[/color]", op_end)
		if cl_start == -1:
			break
		wrapped.append([op_start, cl_start + 8])
		scan = cl_start + 8

	var result: String = bbcode
	for k: int in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[k]
		var s: int = m.get_start()
		var e: int = m.get_end()
		var inside: bool = false
		for r: Array in wrapped:
			if s >= r[0] and e <= r[1]:
				inside = true
				break
		if inside:
			continue
		var token: String = result.substr(s, e - s)
		result = result.substr(0, s) + "[color=#F19320]" + token + "[/color]" + result.substr(e)
	return result


func _fit_praise_font_size() -> void:
	var font_size: int = _PRAISE_BASE_FONT_SIZE
	while font_size >= _PRAISE_MIN_FONT_SIZE:
		_praise.add_theme_font_size_override("normal_font_size", font_size)
		_praise.add_theme_font_size_override("bold_font_size", font_size)
		if _praise.get_content_height() <= _PRAISE_MAX_HEIGHT:
			return
		font_size -= _PRAISE_FONT_STEP


func _format_time(total_sec: int) -> String:
	total_sec = clampi(total_sec, 0, 24 * 3600 - 1)
	var h: int = total_sec / 3600
	var m: int = (total_sec % 3600) / 60
	var s: int = total_sec % 60
	if h > 0:
		return "%02d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]


func _format_score(v: int) -> String:
	return _thousands_fallback(v)


func _thousands_fallback(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	var cnt: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out


func play_appear() -> void:
	_set_next_btn_enabled(false)
	_appear_seq += 1
	if _anim == null or not _anim.has_animation("Appear"):
		_set_next_btn_enabled(true)
		return
	_anim.play("Appear")
	var enable_delay: float = _get_next_btn_ready_time()
	if enable_delay <= 0.0:
		_set_next_btn_enabled(true)
		return
	var seq: int = _appear_seq
	await get_tree().create_timer(enable_delay).timeout
	if seq != _appear_seq:
		return
	_set_next_btn_enabled(true)


func _get_next_btn_ready_time() -> float:
	var anim: Animation = _anim.get_animation("Appear")
	if anim == null or not anim.has_marker(_NEXT_BTN_MARKER):
		return 0.0
	return anim.get_marker_time(_NEXT_BTN_MARKER)


func _set_next_btn_enabled(on: bool) -> void:
	_next_enabled = on
