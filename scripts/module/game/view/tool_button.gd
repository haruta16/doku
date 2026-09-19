# @tool 道具按钮：图标/文字/角标随属性变化实时刷新，另带一段「获得」飞入动画
@tool
class_name ToolButton
extends Control

enum State { NO_TOOL, HAS_TOOL, FREE } # 三态：无道具 / 已拥有 / 免费

# ---- @export 属性（setter 里顺手刷新视图） ----
@export var icon_tex: Texture2D: # 图标贴图
	set(v):
		icon_tex = v
		if is_node_ready():
			$Control/ToolIcon.texture = v
			$ControlObtain/ToolIcon.texture = v

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

@export var icon_size: Vector2 = Vector2(100, 110): # 图标尺寸（像素）
	set(v):
		icon_size = v
		if is_node_ready():
			$Control/ToolIcon.size = v
			$ControlObtain/ToolIcon.size = v

# ---- 对外信号 ----
signal pressed # 点击（已过滤掉缩放反馈）

signal obtain_finished # 获得动画播完

# ---- 运行时状态 ----
var _base_scale: Vector2 = Vector2.ONE # 初始缩放，按压与回弹以它为基准


# ================= 生命周期 =================
# 进树：把属性刷到子节点并接上按压缩放反馈
func _ready() -> void:
	# 把 @export 的值应用到子节点
	if icon_tex != null:
		$Control/ToolIcon.texture = icon_tex
		$ControlObtain/ToolIcon.texture = icon_tex
	$ToolLabel.text = label_text
	$ToolLabelObtain.text = label_text
	$Control/ToolIcon.size = icon_size
	$ControlObtain/ToolIcon.size = icon_size
	_refresh()
	_base_scale = scale
	# 记下初始缩放，接上按下/回弹动画
	$Hit.button_down.connect(func() -> void: UIHelper.play_press_scale(self, _base_scale))
	$Hit.button_up.connect(func() -> void: UIHelper.play_release_scale(self, _base_scale))


# Hit 被按下时转发 pressed
func _on_hit_pressed() -> void:
	pressed.emit()


# 播「获得」动画：图标飞入，播完发 obtain_finished
func play_obtain() -> void:
	# 让获得态图标对齐常态图标的位置
	$ControlObtain/ToolIcon.position = $Control/ToolIcon.position
	var ap: AnimationPlayer = $AnimationPlayer
	# 动画播完再通知外部
	ap.play("Obtain")
	await ap.animation_finished
	obtain_finished.emit()


# ================= 角标刷新 =================
# 按 state / badge_count / AB 配置刷新角标
func _refresh() -> void:
	# 编辑器里不跑运行期逻辑
	if Engine.is_editor_hint():
		return
	# 外部关掉角标就整体隐藏
	if not show_badge:
		$Badge.visible = false
		return
	var is_no_tool: bool = state == State.NO_TOOL
	var is_has_tool: bool = state == State.HAS_TOOL
	var is_free: bool = state == State.FREE
	# 是否需要在广告合规地区显示 AD 标
	var ad_tag: bool = ABTestManager.ad_compliance_ui.should_show_ad_tag()

	$Badge.visible = true
	# 绿色角标：无道具或免费
	var green_badge: GameAdBadge = $Badge/Badge
	green_badge.visible = is_no_tool or is_free
	# 红色角标：显示已拥有数量
	$Badge/RedRoot.visible = is_has_tool
	if is_has_tool:
		# 数量超过 99 显示 99+
		$Badge/RedRoot/CountLabel.text = "99+" if badge_count > 99 else str(badge_count)
	elif is_free:
		green_badge.show_free()
	else:
		# 无道具时按合规配置在 AD 标与 + 号之间切换
		if ad_tag:
			green_badge.show_ad()
		else:
			green_badge.show_plus()


# 设置已拥有数量（走属性 setter，自动刷新角标）
func set_badge_count(count: int) -> void:
	badge_count = count
