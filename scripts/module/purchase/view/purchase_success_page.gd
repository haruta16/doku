## 订阅成功提示页；根据当前权益更新列表并重新排版，关闭时收尾页面表现。

extends UIFrameWindow

const _ROW_KEYS: Array[String] = [
	"PURCHASE_SUCCESS_BENEFIT_NO_BANNER",
	"PURCHASE_SUCCESS_BENEFIT_NO_INTERSTITIAL",
	"PURCHASE_SUCCESS_BENEFIT_LOCATE",
	"PURCHASE_SUCCESS_BENEFIT_HINT",
]

const _LINE_H: float = 68.0
const _ROW_GAP: float = 1.0

const _FIRST_TOP: float = 0.0

const _TXT_W: float = 697.0

const _INFO_H_DESIGN: float = 345.0

const _INFO_H_MIN: float = 4.0 * _LINE_H + 3.0 * _ROW_GAP

const _POPUP_H_DESIGN: float = 1246.0

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _popup: Control = $Content/CommonPopup
@onready var _info: Control = $Content/CommonPopup/Info
@onready var _info_board: Control = $Content/CommonPopup/InfoBoard
@onready var _enjoy_btn: Control = $Content/CommonPopup/EnjoyBtn
@onready var _rows: Array[Control] = [
	$Content/CommonPopup/Info/Row1,
	$Content/CommonPopup/Info/Row2,
	$Content/CommonPopup/Info/Row3,
	$Content/CommonPopup/Info/Row4,
	$Content/CommonPopup/Info/Row5,
]

var _daily_gift_count: int = 1

var _closing: bool = false


func on_show(params: Dictionary = {}) -> void:
	_daily_gift_count = int(params.get("daily_gift_count", 1))
	_refresh_rows()
	_closing = false


func _input(event: InputEvent) -> void:
	if _closing or not is_showing() or _popup == null:
		return
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		pos = (event as InputEventScreenTouch).position
	elif (
		event is InputEventMouseButton
		and event.pressed
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	):
		pos = (event as InputEventMouseButton).position
	else:
		return
	if _popup.get_global_rect().has_point(pos):
		return
	_closing = true

	get_viewport().set_input_as_handled()
	UIManager.hide_ui(UiName.SUBSCRIPTION_SUCCESS)


func on_hide() -> void:
	if _anim != null and _anim.has_animation(&"GenericPopup"):
		_anim.play_section_with_markers(&"GenericPopup", &"Mark", &"")
		await _anim.animation_finished


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_rows()


func _refresh_rows() -> void:
	var texts: PackedStringArray = PackedStringArray()
	texts.append(tr(_ROW_KEYS[0]))
	texts.append(tr(_ROW_KEYS[1]))
	texts.append(tr(_ROW_KEYS[2]) % _daily_gift_count)
	texts.append(tr(_ROW_KEYS[3]) % _daily_gift_count)
	for i in _rows.size():
		var row: Control = _rows[i]
		if row == null:
			continue
		var shown: bool = i < texts.size()
		row.visible = shown
		if shown:
			var lbl: Label = row.get_node_or_null("Txt") as Label
			if lbl != null:
				lbl.text = texts[i]
	_layout_rows()


func _layout_rows() -> void:
	var y: float = _FIRST_TOP
	for row in _rows:
		if row == null or not row.visible:
			continue
		var lbl: Label = row.get_node_or_null("Txt") as Label
		if lbl == null:
			continue
		var h: float = _measure_text_height(lbl)
		row.offset_top = y
		row.offset_bottom = y + h
		lbl.offset_top = 0.0
		lbl.offset_bottom = h
		y += h + _ROW_GAP
	var content_h: float = y - _ROW_GAP - _FIRST_TOP
	var delta: float = maxf(_INFO_H_MIN, content_h) - _INFO_H_DESIGN

	_info.offset_bottom = _info.offset_top + _INFO_H_DESIGN + delta

	_info_board.offset_bottom = _info_board.offset_top + 390.0 + delta

	_enjoy_btn.offset_top = 927.0 + delta
	_enjoy_btn.offset_bottom = 1185.0 + delta

	var half: float = (_POPUP_H_DESIGN + delta) * 0.5
	_popup.offset_top = -half
	_popup.offset_bottom = half


func _measure_text_height(lbl: Label) -> float:
	var font: Font = lbl.get_theme_font(&"font")
	var fs: int = lbl.get_theme_font_size(&"font_size")
	if font == null or lbl.text.is_empty():
		return _LINE_H
	var size: Vector2 = font.get_multiline_string_size(
		lbl.text, HORIZONTAL_ALIGNMENT_LEFT, _TXT_W, fs
	)
	return maxf(_LINE_H, size.y)


func _on_enjoy_pressed() -> void:
	UIManager.hide_ui(UiName.SUBSCRIPTION_SUCCESS)
