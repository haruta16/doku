@tool
class_name ToolButton
extends Control

enum State { NO_TOOL, HAS_TOOL, FREE }

@export var icon_tex: Texture2D:
	set(v):
		icon_tex = v
		if is_node_ready():
			$Control/ToolIcon.texture = v
			$ControlObtain/ToolIcon.texture = v

@export var label_text: String = "":
	set(v):
		label_text = v
		if is_node_ready():
			$ToolLabel.text = v
			$ToolLabelObtain.text = v

@export var state: State = State.NO_TOOL:
	set(v):
		state = v
		if is_node_ready():
			_refresh()

@export var badge_count: int = 0:
	set(v):
		badge_count = v
		if is_node_ready():
			_refresh()

@export var show_badge: bool = true:
	set(v):
		show_badge = v
		if is_node_ready():
			_refresh()

@export var icon_size: Vector2 = Vector2(100, 110):
	set(v):
		icon_size = v
		if is_node_ready():
			$Control/ToolIcon.size = v
			$ControlObtain/ToolIcon.size = v

signal pressed

signal obtain_finished

var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	if icon_tex != null:
		$Control/ToolIcon.texture = icon_tex
		$ControlObtain/ToolIcon.texture = icon_tex
	$ToolLabel.text = label_text
	$ToolLabelObtain.text = label_text
	$Control/ToolIcon.size = icon_size
	$ControlObtain/ToolIcon.size = icon_size
	_refresh()
	_base_scale = scale
	$Hit.button_down.connect(func() -> void: UIHelper.play_press_scale(self, _base_scale))
	$Hit.button_up.connect(func() -> void: UIHelper.play_release_scale(self, _base_scale))


func _on_hit_pressed() -> void:
	pressed.emit()


func play_obtain() -> void:
	$ControlObtain/ToolIcon.position = $Control/ToolIcon.position
	var ap: AnimationPlayer = $AnimationPlayer
	ap.play("Obtain")
	await ap.animation_finished
	obtain_finished.emit()


func _refresh() -> void:
	if Engine.is_editor_hint():
		return
	if not show_badge:
		$Badge.visible = false
		return
	var is_no_tool: bool = state == State.NO_TOOL
	var is_has_tool: bool = state == State.HAS_TOOL
	var is_free: bool = state == State.FREE
	var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()

	$Badge.visible = true
	var green_badge: GameAdBadge = $Badge/Badge
	green_badge.visible = is_no_tool or is_free
	$Badge/RedRoot.visible = is_has_tool
	if is_has_tool:
		$Badge/RedRoot/CountLabel.text = "99+" if badge_count > 99 else str(badge_count)
	elif is_free:
		green_badge.show_free()
	else:
		if ad_tag:
			green_badge.show_ad()
		else:
			green_badge.show_plus()


func set_badge_count(count: int) -> void:
	badge_count = count
