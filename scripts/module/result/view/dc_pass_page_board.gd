## 每日挑战结算面板：显示挑战统计与重玩入口，并适配标题和标签宽度。
class_name DcPassPageBoard
extends PassPageG1Board

signal replay_pressed

const _TITLE_MAX_WIDTH: float = 550.0
const _TITLE_BASE_FONT_SIZE: int = 80
const _TITLE_MIN_FONT_SIZE: int = 40
const _TITLE_FONT_STEP: int = 4

const _KEY_MAX_WIDTH: float = 400.0
const _KEY_BASE_FONT_SIZE: int = 56
const _KEY_MIN_FONT_SIZE: int = 40
const _KEY_FONT_STEP: int = 4

@onready var _dc_time_key: Label = $ContentGroup/Popup/StatsPanel/StatRow2/Cells/KeyLabel
@onready var _dc_time_value: Label = $ContentGroup/Popup/StatsPanel/StatRow2/Cells/ValueLabel
@onready var _dc_beat_key: Label = $ContentGroup/Popup/StatsPanel/StatRow3/Cells/KeyLabel
@onready var _dc_beat_value: Label = $ContentGroup/Popup/StatsPanel/StatRow3/Cells/ValueLabel

@onready var _replay_btn: Control = $ContentGroup/CtaRow/ReplayBtn
@onready var _cta_row: Control = $ContentGroup/CtaRow

const _REPLAY_CTA_RISE: float = 120.0

var _cta_base_offsets: Vector2 = Vector2.ZERO


func _ready() -> void:
	var shine: Node2D = $ContentGroup/Sprite2D/Shine2
	var title: Control = $ContentGroup/Popup/TitleLabel
	_sprite2d_y_offset_from_popup = title.position.y + title.size.y * 0.5 - shine.position.y
	_cta_base_offsets = Vector2(_cta_row.offset_top, _cta_row.offset_bottom)

	if _replay_btn != null and _replay_btn.has_signal("tag_pressed"):
		_replay_btn.tag_pressed.connect(_on_replay_tag_pressed)
	super._ready()


func set_replay_available(available: bool) -> void:
	if _cta_base_offsets == Vector2.ZERO:
		_cta_base_offsets = Vector2(_cta_row.offset_top, _cta_row.offset_bottom)
	var rise: float = _REPLAY_CTA_RISE if available else 0.0
	_cta_row.offset_top = _cta_base_offsets.x - rise
	_cta_row.offset_bottom = _cta_base_offsets.y - rise
	_replay_btn.visible = available


func _on_replay_tag_pressed() -> void:
	if _next_enabled:
		replay_pressed.emit()


func _apply_stat_key_labels() -> void:
	super._apply_stat_key_labels()
	_dc_time_key.text = tr("PASS_PAGE_TIME")
	_dc_beat_key.text = tr("PASS_PAGE_BEAT")
	_fit_stat_key_font_size()


func _fit_stat_key_font_size() -> void:
	var font: Font = _size_key.get_theme_font("font")
	if font == null:
		push_error("DcPassPageBoard: KeyLabel 取不到字体,行标签单行兜底跳过")
		return
	var labels: Array[Label] = [_size_key, _time_key, _score_key, _combo_key]
	var font_size: int = _KEY_BASE_FONT_SIZE
	while font_size > _KEY_MIN_FONT_SIZE:
		var widest: float = 0.0
		for lbl: Label in labels:
			widest = maxf(
				widest, font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			)
		if widest <= _KEY_MAX_WIDTH:
			break
		font_size -= _KEY_FONT_STEP
	for lbl: Label in labels:
		lbl.add_theme_font_size_override("font_size", font_size)


func populate(
	title_text: String,
	praise_bbcode: String,
	next_label: String,
	next_is_hard: bool,
	stats: Dictionary,
	is_next_golden: bool = false
) -> void:
	super.populate(title_text, praise_bbcode, next_label, next_is_hard, stats, is_next_golden)

	_dc_time_value.text = _format_time(int(stats.get("elapsed_sec", 0)))

	_dc_beat_value.text = I18nFormat.percent(float(stats.get("beat_percent", 0.0)), 1)

	_fit_title_font_size()


func _fit_title_font_size() -> void:
	var font: Font = _title.get_theme_font("font")
	if font == null:
		push_error("DcPassPageBoard: TitleLabel 取不到字体,标题单行自适应跳过")
		return
	var font_size: int = _TITLE_BASE_FONT_SIZE
	while font_size > _TITLE_MIN_FONT_SIZE:
		if (
			font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			<= _TITLE_MAX_WIDTH
		):
			break
		font_size -= _TITLE_FONT_STEP
	_title.add_theme_font_size_override("font_size", font_size)


func show_and_play_appear() -> void:
	visible = true
	if _anim != null and _anim.has_animation("Appear"):
		_anim.stop()
		_anim.play("Appear")
		_anim.advance(0.0)
		_anim.pause()
	play_appear()
