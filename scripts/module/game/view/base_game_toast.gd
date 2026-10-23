## 开局提示卡基类：封装动画、卡片选择、文案定位及显隐时序。
class_name BaseGameToast
extends CanvasLayer

# ---- 动画标记约定 ----
const DISAPPEAR_MARKER: StringName = &"Disappear" # 退场标记名：播到这里就可以开始消失

const DISAPPEAR_MARKER_FALLBACK: StringName = &"Mark" # 退场标记的备用名

var _current_hold_sec: float = NormalStartToastConfig.HOLD_DEFAULT

var _default_card_y: float = 0.0

# ---- 子节点引用 ----
@onready var _root: Control = $Root # 整体根节点，接收点击
@onready var _card: Control = $Root/Card # 卡片容器，决定弹窗位置
@onready var _anim_player: AnimationPlayer = $AnimationPlayer # 动画播放器

const _CARD_NAMES: Array[String] = ["Card6", "Card7", "Card11"]

var _label: RichTextLabel = null # 当前卡片里的文案节点，选卡后才有值

@export var sibling_toast: CanvasLayer # 兄弟 Toast：显示前先关掉它，避免叠加

var _seq_token: int = 0 # 播放序号，用来作废过期的异步等待


func _ready() -> void:
	_anim_player.animation_finished.connect(_on_anim_finished)
	_default_card_y = _card.position.y
	_on_ready_extra()


# ================= 子类覆写点与动画解析 =================
## 子类返回默认入场动画名
func _appear_anim() -> StringName:
	return &""


## 取动画里的退场标记时间；没有标记返回 -1
func _disappear_marker_time(anim: Animation) -> float:
	if anim == null:
		return -1.0
	# 优先 Disappear，老动画退回 Mark
	if anim.has_marker(DISAPPEAR_MARKER):
		return anim.get_marker_time(DISAPPEAR_MARKER)
	if anim.has_marker(DISAPPEAR_MARKER_FALLBACK):
		return anim.get_marker_time(DISAPPEAR_MARKER_FALLBACK)
	return -1.0


## 子类返回埋点用的弹窗名
func _dlg_name() -> String:
	return ""


func _label_subpaths() -> Dictionary:
	return {}


func _apply_text(params: Dictionary) -> void:
	var text_key: String = params.get("text_key", "GAME_TOAST_FIRST_TRY")
	var pct_str: String = params.get("pct_str", "")
	var source_text: String = tr(text_key)
	if source_text == text_key:
		source_text = params.get("fallback_text", source_text)
	var text: String = TextHighlightRenderer.render(
		ABTestManager.text_highlight, text_key, source_text, "#FFEE00"
	)
	if pct_str.is_empty():
		_label.text = text
	elif text.contains("{0}"):
		_label.text = text.replace("{0}", "[color=#ffee00][b]%s[/b][/color]" % pct_str)
	else:
		_label.text = text % pct_str


## 子类可选的进树钩子
func _on_ready_extra() -> void:
	pass


# ================= 展示与隐藏 =================
## 把卡片左上角移到指定位置
func set_card_position(top_left: Vector2) -> void:
	if _card != null:
		_card.position = top_left


## 把卡片中心对准指定位置
func set_card_center(center: Vector2) -> void:
	if _card != null:
		_card.position = center - _card.size * 0.5


func show_toast(params: Dictionary = {}) -> void:
	if sibling_toast != null and is_instance_valid(sibling_toast) and sibling_toast.visible:
		if sibling_toast.has_method("hide_toast"):
			sibling_toast.hide_toast()
	visible = true

	_select_variant_card()
	_apply_text(params)

	_apply_card_position()

	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seq_token += 1
	_play_entry_anim(_seq_token)


func _select_variant_card() -> void:
	var target: String = NormalStartToastConfig.CARD_BASELINE
	for card_name in _CARD_NAMES:
		var c: Control = _card.get_node_or_null(card_name) as Control
		if c != null:
			c.visible = (card_name == target)

	var subpath: String = _label_subpaths().get(target, "")
	_label = _card.get_node_or_null("%s/%s" % [target, subpath]) as RichTextLabel


func _apply_card_position() -> void:
	_card.position.y = _default_card_y


func hide_toast() -> void:
	if not visible:
		return
	visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seq_token += 1
	_anim_player.stop()


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == _appear_anim():
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if visible:
			visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var pressed: bool = (
		(event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	)
	if pressed:
		_skip_to_disappear()


func _skip_to_disappear() -> void:
	var appear: StringName = _appear_anim()
	if _anim_player.assigned_animation != appear:
		return
	var anim: Animation = _anim_player.get_animation(appear)
	if anim == null:
		return
	var marker_time: float = _disappear_marker_time(anim)
	var cur: float = _anim_player.current_animation_position

	if cur >= marker_time and _anim_player.is_playing():
		return
	_seq_token += 1

	if cur < marker_time:
		_anim_player.seek(marker_time, true)
	_anim_player.play(appear)


func _play_entry_anim(token: int) -> void:
	var appear: StringName = _appear_anim()
	var anim: Animation = _anim_player.get_animation(appear)
	if anim == null:
		return
	var marker_time: float = _disappear_marker_time(anim)
	if marker_time < 0.0:
		_anim_player.play(appear)
		return
	_anim_player.play(appear)
	await get_tree().create_timer(marker_time).timeout
	if token != _seq_token or not is_inside_tree() or not visible:
		return
	_anim_player.pause()
	await get_tree().create_timer(_current_hold_sec).timeout
	if token != _seq_token or not is_inside_tree() or not visible:
		return
	_anim_player.play(appear)


func nominal_visible_sec() -> float:
	var anim: Animation = _anim_player.get_animation(_appear_anim())
	if anim == null:
		return 0.0
	return _current_hold_sec + anim.length
