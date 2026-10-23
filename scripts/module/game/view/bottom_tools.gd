## 底部道具栏：按当前玩法同步可见槽位、锁定、选中、数量和广告可用状态。
class_name BottomTools
extends HBoxContainer

signal locate_pressed
signal hint_pressed
signal mouse_pressed
signal draft_pressed

const _ANIM_IDLE_LOOP: String = "tool_loop"
const _ANIM_RESET: String = "RESET"

const _SEPARATION_BY_VISIBLE: Dictionary = {
	2: 168,
	3: 72,
	4: 40,
}
const _SEPARATION_FALLBACK: int = 168

@onready var _locate_ctrl: Control = $RevealCtrl
@onready var _hint_ctrl: Control = $HintCtrl
@onready var _mouse_ctrl: Control = $MouseCtrl
@onready var _draft_ctrl: Control = $DraftCtrl
@onready var _locate_btn: ToolButton = $RevealCtrl/RevealBtn
@onready var _hint_btn: ToolButton = $HintCtrl/HintBtn
@onready var _mouse_btn: ToolButton = $MouseCtrl/MouseBtn
@onready var _draft_btn: ToolButton = $DraftCtrl/DraftBtn

var _idle_hint_btn: ToolButton = null


func _ready() -> void:
	_refresh_separation()


func _get_btn(kind: String) -> ToolButton:
	match kind:
		ToolKind.LOCATE:
			return _locate_btn
		ToolKind.HINT:
			return _hint_btn
		ToolKind.MOUSE:
			return _mouse_btn
		ToolKind.DRAFT:
			return _draft_btn
	return null


func _visible_slot_count() -> int:
	var n: int = 0
	for kind: String in ToolKind.ALL:
		var slot: Control = _get_slot(kind)
		if slot != null and slot.visible:
			n += 1
	return n


func _refresh_separation() -> void:
	var n: int = _visible_slot_count()
	var sep: int = _SEPARATION_BY_VISIBLE.get(n, _SEPARATION_FALLBACK)
	add_theme_constant_override("separation", sep)


func _get_slot(kind: String) -> Control:
	match kind:
		ToolKind.LOCATE:
			return _locate_ctrl
		ToolKind.HINT:
			return _hint_ctrl
		ToolKind.MOUSE:
			return _mouse_ctrl
		ToolKind.DRAFT:
			return _draft_ctrl
	return null


func set_kind_enabled(kind: String, enabled: bool) -> void:
	var slot: Control = _get_slot(kind)
	if slot == null or slot.visible == enabled:
		return
	slot.visible = enabled
	_refresh_separation()


func set_hint_first(hint_first: bool) -> void:
	var lead: Control = _hint_ctrl if hint_first else _locate_ctrl
	if lead == null:
		return
	move_child(lead, 0)


func set_kind_locked(kind: String, locked: bool, unlock_level: int = 0) -> void:
	var tb: ToolButton = _get_btn(kind)
	if tb != null:
		tb.set_locked(locked, unlock_level)


func set_kind_selected(kind: String, selected: bool) -> void:
	var tb: ToolButton = _get_btn(kind)
	if tb != null:
		tb.set_selected(selected)


func set_ad_unavailable(unavailable: bool) -> void:
	for kind in [ToolKind.LOCATE, ToolKind.HINT, ToolKind.MOUSE, ToolKind.DRAFT]:
		var tb: ToolButton = _get_btn(kind)
		if tb != null:
			tb.set_ad_unavailable(unavailable)


func sync_from_state(free_kinds: Array[String] = []) -> void:
	for kind: String in ToolKind.ALL:
		var tb: ToolButton = _get_btn(kind)
		if tb == null:
			continue
		var count: int = GameState.get_tool_count(kind)
		if count > 0:
			tb.state = ToolButton.State.HAS_TOOL
			tb.set_badge_count(count)
		else:
			tb.badge_count = 0
			tb.state = ToolButton.State.NO_TOOL

	for kind: String in free_kinds:
		_set_state(kind, ToolButton.State.FREE)


func refresh_kind(kind: String, count: int) -> void:
	var tb: ToolButton = _get_btn(kind)
	if tb == null or tb.state == ToolButton.State.FREE:
		return
	if count > 0:
		tb.set_badge_count(count)
		tb.state = ToolButton.State.HAS_TOOL
	else:
		tb.badge_count = 0
		tb.state = ToolButton.State.NO_TOOL


func _set_state(kind: String, state: ToolButton.State) -> void:
	var tb: ToolButton = _get_btn(kind)
	if tb != null:
		tb.state = state


func play_idle_hint(kind: String) -> bool:
	var tb: ToolButton = _get_btn(kind)
	if tb == null:
		return false
	var ap: AnimationPlayer = tb.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(_ANIM_IDLE_LOOP):
		return false
	ap.play(_ANIM_IDLE_LOOP)
	_idle_hint_btn = tb
	return true


func stop_idle_hint() -> void:
	if _idle_hint_btn == null:
		return
	var ap: AnimationPlayer = _idle_hint_btn.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation(_ANIM_RESET):
		ap.play(_ANIM_RESET)
	_idle_hint_btn = null


func is_idle_hint_playing() -> bool:
	return _idle_hint_btn != null


func _on_reveal_btn_pressed() -> void:
	locate_pressed.emit()


func _on_hint_btn_pressed() -> void:
	hint_pressed.emit()


func _on_mouse_btn_pressed() -> void:
	mouse_pressed.emit()


func _on_draft_btn_pressed() -> void:
	draft_pressed.emit()
