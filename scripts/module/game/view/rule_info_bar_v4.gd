# 规则信息条（V4）：可折叠的规则说明，折叠状态持久化在存档里
class_name RuleInfoBarV4
extends Control

# ---- 子节点引用 ----
@onready var _control: Control = $Control # 会左右移动的内容容器
@onready var _arrow: TextureRect = $Control/Arrow # 折叠箭头
@onready var _hit: Button = $Control/Hit # 点击热区

# ---- 运行时状态 ----
var _collapsed: bool = false # 当前是否折叠
var _tween: Tween # 折叠/展开用的 Tween

var _interactive: bool = true # 是否响应点击


# 进树：接点击，并按存档状态先归位
func _ready() -> void:
	_hit.pressed.connect(_on_hit_pressed)
	apply_persisted_state.call_deferred()


# 外部开关交互（例如结算动画期间禁用）
func set_interactive(enabled: bool) -> void:
	_interactive = enabled


# ================= 折叠状态 =================
# 按存档里的折叠状态直接摆好位置（不动画）
func apply_persisted_state() -> void:
	_collapsed = GameState.is_rule_info_bar_collapsed()
	var target_x: float = size.x - _hit.size.x if _collapsed else 0.0
	_control.position.x = target_x
	# 箭头方向跟着状态走
	_arrow.flip_h = _collapsed


# ================= 交互与动画 =================
# 点击热区：折叠状态取反
func _on_hit_pressed() -> void:
	# 禁用状态直接忽略
	if not _interactive:
		return
	# 动画进行中忽略
	if _tween and _tween.is_running():
		return
	if _collapsed:
		_play_expand()
	else:
		_play_collapse()


# 折叠：写存档并播动画
func _play_collapse() -> void:
	_collapsed = true
	# 立刻写存档，动画中途退出也不丢状态
	GameState.set_rule_info_bar_collapsed(true)
	# 折叠后只露出右侧热区
	var target_x: float = size.x - _hit.size.x
	_tween = create_tween()
	(
		_tween
		. tween_property(_control, "position:x", target_x, 0.3)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	# 动画尾声再翻箭头
	_tween.parallel().tween_callback(_flip_arrow_collapsed).set_delay(0.28)


# 展开：写存档并播动画（先向左过冲再回位）
func _play_expand() -> void:
	_collapsed = false
	# 立刻写存档
	GameState.set_rule_info_bar_collapsed(false)
	_tween = create_tween()
	# 先向左过冲 10 像素，再回到 0
	(
		_tween
		. tween_property(_control, "position:x", -10.0, 0.25)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	_tween.tween_callback(_flip_arrow_expanded)
	_tween.tween_property(_control, "position:x", 0.0, 0.1).set_ease(Tween.EASE_IN_OUT).set_trans(
		Tween.TRANS_QUAD
	)


# 箭头翻到折叠方向
func _flip_arrow_collapsed() -> void:
	_arrow.flip_h = true


# 箭头翻回展开方向
func _flip_arrow_expanded() -> void:
	_arrow.flip_h = false
