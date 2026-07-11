class_name RuleSwipeCard
extends Control

const _DX: float = 890.0
const _OVERSHOOT: float = 10.0
const _OUT_SEC: float = 0.3
const _IN_BACK_SEC: float = 0.16
const _DOT_FADE_SEC: float = 0.06
const _DOT_DIM: float = 0.3
const _SWIPE_THRESHOLD: float = 50.0

const _DEFAULT_RULE: int = 2

const _RULE_TEX: Array[Texture2D] = [
	preload("res://assets/sprites/game/rule_diagram_color.png"),
	preload("res://assets/sprites/game/rule_diagram_line.png"),
	preload("res://assets/sprites/game/rule_diagram_touch.png"),
]

@onready var _clip: Control = $Clip
@onready var _contents: Array[Control] = [$Clip/Content0, $Clip/Content1]
@onready var _dots: Array[TextureButton] = [$Dots/Dot0, $Dots/Dot1, $Dots/Dot2]

var _rules: Array = []
var _cur: int = 0
var _active: int = 0
var _tween: Tween = null
var _press_x: float = 0.0
var _pressing: bool = false


func _ready() -> void:
	for i in range(_dots.size()):
		_dots[i].pressed.connect(_on_dot_pressed.bind(i))


func setup(texts: Array) -> void:
	_rules = []
	for i in range(texts.size()):
		var tex: Texture2D = _RULE_TEX[i] if i < _RULE_TEX.size() else null
		_rules.append({"texture": tex, "text": str(texts[i])})
	_kill_tween()
	_cur = clampi(_DEFAULT_RULE, 0, maxi(_rules.size() - 1, 0))
	_active = 0
	for i in range(_contents.size()):
		_contents[i].position.x = 0.0
		_contents[i].visible = (i == _active)
	_fill_content(_contents[_active], _cur)
	_refresh_dots(true)


const _LABEL_MEASURE_W: float = 848.0


func _fill_content(content: Control, rule_idx: int) -> void:
	if rule_idx < 0 or rule_idx >= _rules.size():
		return
	var rule: Dictionary = _rules[rule_idx]
	var diagram := content.get_node("Diagram") as TextureRect
	var holder := content.get_node("LabelHolder") as Control
	var label := content.get_node("LabelHolder/Label") as Label
	diagram.texture = rule.get("texture", null)

	holder.custom_minimum_size.x = _LABEL_MEASURE_W
	holder.size.x = _LABEL_MEASURE_W
	label.text = str(rule.get("text", ""))
	if label is AutoFitLabel:
		(label as AutoFitLabel).refit()

	var font: Font = label.get_theme_font(&"font")
	var fs: int = label.get_theme_font_size(&"font_size")
	var disp: String = label.atr(label.text)
	var text_w: float = ceil(
		font.get_multiline_string_size(disp, HORIZONTAL_ALIGNMENT_CENTER, _LABEL_MEASURE_W, fs).x
	)
	holder.custom_minimum_size.x = text_w
	holder.size.x = text_w
	content.queue_sort()


func _go_to(target: int) -> void:
	target = clampi(target, 0, _rules.size() - 1)
	if target == _cur or _rules.is_empty():
		return
	var dir: int = 1 if target > _cur else -1
	_kill_tween()
	var out_layer: Control = _contents[_active]
	var in_layer: Control = _contents[1 - _active]
	_fill_content(in_layer, target)
	in_layer.position.x = float(dir) * _DX
	in_layer.visible = true
	out_layer.visible = true
	var overshoot: float = -float(dir) * _OVERSHOOT
	_tween = create_tween()
	_tween.set_parallel(true)

	(
		_tween
		. tween_property(out_layer, "position:x", -float(dir) * _DX, _OUT_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)

	(
		_tween
		. tween_property(in_layer, "position:x", overshoot, _OUT_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)

	(
		_tween
		. tween_property(in_layer, "position:x", 0.0, _IN_BACK_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
		. set_delay(_OUT_SEC)
	)
	var settled_out := out_layer
	_tween.finished.connect(func() -> void: settled_out.visible = false)
	_active = 1 - _active
	_cur = target
	_refresh_dots(false)


func _refresh_dots(instant: bool) -> void:
	for i in range(_dots.size()):
		var target_a: float = 1.0 if i == _cur else _DOT_DIM
		if instant:
			_dots[i].modulate.a = target_a
		else:
			var tw := create_tween()
			tw.tween_property(_dots[i], "modulate:a", target_a, _DOT_FADE_SEC)


func _on_dot_pressed(index: int) -> void:
	_go_to(index)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_pressing = true
			_press_x = t.position.x
		elif _pressing:
			_pressing = false
			_resolve_swipe(t.position.x - _press_x)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_x = mb.position.x
			elif _pressing:
				_pressing = false
				_resolve_swipe(mb.position.x - _press_x)


func _resolve_swipe(dx: float) -> void:
	if dx <= -_SWIPE_THRESHOLD:
		_go_to(_cur + 1)
	elif dx >= _SWIPE_THRESHOLD:
		_go_to(_cur - 1)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
