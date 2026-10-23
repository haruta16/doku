## 金鱼玩法说明卡：生成高亮比例文案，响应关闭输入并清理动画。
class_name GoldenFishTutorialCard
extends CanvasLayer

signal dismissed

const _RATIO_KEY: String = "GOLDEN_FISH_TUTORIAL_RATIO"
const _RATIO_FALLBACK: String = "{0} Golden Fish counts as {1} Fishes"

const _HL_FONT_SIZE: int = 60

const _FADE_IN_SEC: float = 0.2
const _FADE_OUT_SEC: float = 0.15

const _CLICK_DELAY_SEC: float = 0.5

@onready var _root: Control = $Root

@onready var _ratio_label: AutoFitRichTextLabel = $Root/Card/RatioLabel

var _click_allowed: bool = false

var _closing: bool = false

var _tw: Tween = null


func show_card() -> void:
	_kill_tween()
	_closing = false
	_click_allowed = false

	_ratio_label.text = ratio_text()
	visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.modulate.a = 0.0
	_tw = create_tween()
	_tw.tween_property(_root, "modulate:a", 1.0, _FADE_IN_SEC)
	get_tree().create_timer(_FADE_IN_SEC + _CLICK_DELAY_SEC).timeout.connect(
		func() -> void:
			if is_instance_valid(self) and visible and not _closing:
				_click_allowed = true
	)


func ratio_text() -> String:
	var tpl: String = TranslationServer.translate(_RATIO_KEY)
	if tpl == _RATIO_KEY:
		tpl = _RATIO_FALLBACK
	return tpl.format([_hl(1), _hl(RankActivityConfig.GOLDEN_FISH_COLLECT_RATIO)])


static func _hl(n: int) -> String:
	return "[b][color=#f19320][font_size=%d]%d[/font_size][/color][/b]" % [_HL_FONT_SIZE, n]


func _on_root_gui_input(event: InputEvent) -> void:
	if not _click_allowed or _closing:
		return
	var pressed: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if not pressed:
		return
	_root.accept_event()
	_close()


func _close() -> void:
	_closing = true
	_click_allowed = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	_tw = create_tween()
	_tw.tween_property(_root, "modulate:a", 0.0, _FADE_OUT_SEC)
	await _tw.finished
	visible = false
	dismissed.emit()


func reset_card() -> void:
	var was_visible: bool = visible
	_kill_tween()
	_closing = false
	_click_allowed = false
	visible = false
	if _root != null:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.modulate.a = 1.0
	if was_visible:
		dismissed.emit()


func _kill_tween() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null
