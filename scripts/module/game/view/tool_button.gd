## 道具按钮：同步数量、锁定、选中和广告状态，转发有效点击并播放获得反馈。
@tool
class_name ToolButton
extends Control

enum State { NO_TOOL, HAS_TOOL, FREE } # 三态：无道具 / 已拥有 / 免费

@export var icon_tex: Texture2D:
	set(v):
		icon_tex = v
		if is_node_ready():
			$Control/ToolIcon.texture = v
			$ControlObtain/ToolIcon.texture = v
			$Locked/ToolIcon.texture = v

@export var label_text: String = "": # 按钮文字
	set(v):
		label_text = v
		if is_node_ready():
			$ToolLabel.text = v
			$ToolLabelObtain.text = v

@export var state: State = State.NO_TOOL: # 当前状态，见 State
	set(v):
		state = v
		if is_node_ready():
			_refresh()

@export var badge_count: int = 0: # 已拥有数量，显示在红色角标上
	set(v):
		badge_count = v
		if is_node_ready():
			_refresh()

@export var show_badge: bool = true: # 是否显示角标
	set(v):
		show_badge = v
		if is_node_ready():
			_refresh()

# ---- 对外信号 ----
signal pressed # 点击（已过滤掉缩放反馈）

signal obtain_finished # 获得动画播完

var _ad_unavailable: bool = false

var _animate_badge_switch: bool = false

var _locked: bool = false

# ---- 运行时状态 ----
var _base_scale: Vector2 = Vector2.ONE # 初始缩放，按压与回弹以它为基准


func _ready() -> void:
	if icon_tex != null:
		$Control/ToolIcon.texture = icon_tex
		$ControlObtain/ToolIcon.texture = icon_tex
		$Locked/ToolIcon.texture = icon_tex
	$ToolLabel.text = label_text
	$ToolLabelObtain.text = label_text
	_refresh()
	_base_scale = scale
	$Hit.button_down.connect(func() -> void: UIHelper.play_press_scale(self, _base_scale))
	$Hit.button_up.connect(func() -> void: UIHelper.play_release_scale(self, _base_scale))


## Hit 被按下时转发 pressed
func _on_hit_pressed() -> void:
	pressed.emit()


## 播「获得」动画：图标飞入，播完发 obtain_finished
func play_obtain() -> void:
	# 让获得态图标对齐常态图标的位置
	$ControlObtain/ToolIcon.position = $Control/ToolIcon.position
	var ap: AnimationPlayer = $AnimationPlayer
	# 动画播完再通知外部
	ap.play("Obtain")
	await ap.animation_finished
	obtain_finished.emit()


func _refresh() -> void:
	if Engine.is_editor_hint():
		return

	var animate_switch: bool = _animate_badge_switch
	_animate_badge_switch = false

	$Locked.visible = _locked
	$Control/ToolIcon.visible = not _locked
	if _locked:
		$Badge.visible = false
		return
	if not show_badge:
		$Badge.visible = false
		return
	var is_no_tool: bool = state == State.NO_TOOL
	var is_has_tool: bool = state == State.HAS_TOOL
	var is_free: bool = state == State.FREE
	$Badge.visible = true
	var green_badge: GameAdBadge = $Badge/Badge

	if _selected:
		green_badge.visible = true
		$Badge/RedRoot.visible = false
		green_badge.show_on()
		return
	green_badge.visible = is_no_tool or is_free
	$Badge/RedRoot.visible = is_has_tool
	if is_has_tool:
		$Badge/RedRoot/CountLabel.text = "99+" if badge_count > 99 else str(badge_count)
	elif is_free:
		green_badge.show_free()
	elif _ad_unavailable:
		green_badge.show_no_network(animate_switch)
	else:
		green_badge.show_ad(animate_switch)


## 设置已拥有数量（走属性 setter，自动刷新角标）
func set_badge_count(count: int) -> void:
	badge_count = count


func set_locked(locked: bool, unlock_level: int = 0) -> void:
	_locked = locked
	if locked:
		$Locked/LockedLv.text = "Lv.%d" % unlock_level
	if is_node_ready():
		_refresh()


func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	if is_node_ready():
		_refresh()


func is_selected() -> bool:
	return _selected


func set_ad_unavailable(unavailable: bool) -> void:
	if _ad_unavailable == unavailable:
		return
	_ad_unavailable = unavailable
	if is_node_ready():
		_animate_badge_switch = true
		_refresh()


var _selected: bool = false
