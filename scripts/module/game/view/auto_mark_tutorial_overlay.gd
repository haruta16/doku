# 自动标记新手引导：把目标列与按钮抬到遮罩之上，用手型动画指路，点任意处关闭并回传是否点中按钮
class_name AutoMarkTutorialOverlay
extends Control

# ---- z 层级偏移（相对父节点） ----
const _Z_DELTA_MASK: int = 400 # 遮罩层
const _Z_DELTA_HOIST: int = 500 # 被抬起的格子/按钮
const _Z_DELTA_HAND: int = 600 # 手型与气泡

# ---- 资源与位置 ----
const _POP_UP_TOAST_SCENE: PackedScene = preload("res://assets/prefab/pop_up_toast.tscn") # 气泡提示场景

const _TOAST_Y_ABOVE_BOARD: float = 170.0 # 气泡在棋盘上方多少像素

# ---- 子节点引用 ----
@onready var _mask: ColorRect = $Mask # 全屏遮罩
@onready var _hand_hint: Control = $HandHint # 手型引导
@onready var _hand_spine: Node = $HandHint/ui_guide_hand # 手型的骨骼动画节点

signal closed(hit_btn: bool) # 关闭时回传是否点中自动标记按钮

# ---- 运行时状态 ----
var _hoisted: Array = [] # 被抬起过的节点及其原 z 值
var _is_closed: bool = false # 是否已关闭，防止重复响应输入

var _btn_hit_rect: Rect2 = Rect2() # 目标按钮的屏幕矩形

var _toast: PopUpToast = null # 顶部气泡提示


# 进树；具体引导由 setup 驱动
func _ready() -> void:
	pass


# ================= 引导入口 =================
# 对某一列的自动标记按钮做引导；参数非法时打错误日志并放弃
func setup(board_view: BoardView, col: int) -> void:
	if board_view == null:
		push_error("[AutoMarkTutorialOverlay] setup: board_view == null")
		return
	# 列号必须在盘面范围内
	var sz: int = board_view.get_puzzle_size()
	if sz <= 0 or col < 0 or col >= sz:
		push_error("[AutoMarkTutorialOverlay] setup: invalid col=%d sz=%d" % [col, sz])
		return
	# 以父节点的 z_index 为基准
	var base_z: int = _resolve_base_z()

	_mask.z_index = base_z + _Z_DELTA_MASK
	_mask.z_as_relative = false
	_hand_hint.z_index = base_z + _Z_DELTA_HAND
	_hand_hint.z_as_relative = false

	# 把这一列的格子抬到遮罩之上
	for r in range(sz):
		var cell: CellView = board_view.get_cell_view(r, col)
		if cell != null:
			_hoist(cell, base_z)

	# 按钮也抬起来，保证可见
	var btn: Control = board_view.get_axis_auto_mark_btn(1, col)
	if btn != null:
		_hoist(btn, base_z)

	# 记下按钮矩形，把手型摆到按钮上方
	var btn_rect: Rect2 = board_view.get_axis_auto_mark_btn_global_rect(1, col)
	if btn_rect.size != Vector2.ZERO:
		_btn_hit_rect = btn_rect
		var hx: float = btn_rect.get_center().x - _hand_hint.size.x * 0.5 + 65
		var hy: float = btn_rect.position.y - _hand_hint.size.y + 40.0 + 102
		_hand_hint.global_position = Vector2(hx, hy)

	# 手型播点击动作
	if _hand_spine != null and _hand_spine.has_method("get_animation_state"):
		_hand_spine.get_animation_state().set_animation("click", true, 0)

	# 再弹一条文字提示
	_spawn_toast(board_view, base_z)


# ================= 内部工具 =================
# 取父节点 z_index 作为基准（没有就按 0）
func _resolve_base_z() -> int:
	var p: Node = get_parent()
	if p == null or not "z_index" in p:
		return 0
	return p.z_index


# 在棋盘上方弹一条气泡提示
func _spawn_toast(board_view: BoardView, base_z: int) -> void:
	_toast = _POP_UP_TOAST_SCENE.instantiate() as PopUpToast
	add_child(_toast)

	# 锚点置顶居中
	_toast.anchor_left = 0.5
	_toast.anchor_top = 0.0
	_toast.anchor_right = 0.5
	_toast.anchor_bottom = 0.0
	_toast.offset_left = 0.0
	_toast.offset_right = 0.0
	_toast.offset_bottom = 0.0

	# 贴到棋盘上方
	var board_top_y: float = board_view.global_position.y
	_toast.offset_top = board_top_y - _TOAST_Y_ABOVE_BOARD

	_toast.z_index = base_z + _Z_DELTA_HAND
	_toast.z_as_relative = false

	# 填文案并弹出
	_toast.set_text(tr("AUTO_MARK_TUTORIAL"))
	_toast.pop_up()


# 把一个节点抬到遮罩之上，并记住它原来的 z 值
func _hoist(node: CanvasItem, base_z: int) -> void:
	_hoisted.append({"node": node, "prev_z": node.z_index, "prev_rel": node.z_as_relative})
	node.z_as_relative = false
	node.z_index = base_z + _Z_DELTA_HOIST


# 还原所有被抬起的节点
func _restore_z() -> void:
	for entry in _hoisted:
		var node: CanvasItem = entry["node"] as CanvasItem
		if not is_instance_valid(node):
			continue
		node.z_index = entry["prev_z"]
		node.z_as_relative = entry["prev_rel"]
	_hoisted.clear()


# ================= 输入与关闭 =================
# 全局输入：点任意位置都关闭引导，并回传是否点中按钮
func _input(event: InputEvent) -> void:
	if _is_closed:
		return
	# 只处理按下事件
	var pressed: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	# 非按下就忽略
	if not pressed:
		return

	# 取点击坐标（鼠标或触摸）
	var pos: Vector2 = (
		event.position
		if event is InputEventMouseButton
		else (event as InputEventScreenTouch).position
	)
	# 判断是否落在按钮矩形内
	var hit_btn: bool = _btn_hit_rect.size != Vector2.ZERO and _btn_hit_rect.has_point(pos)
	# 只处理一次，吃掉这次输入
	_is_closed = true
	get_viewport().set_input_as_handled()
	# 先还原 z 值
	_restore_z()

	_detach_and_dismiss_toast()
	# 通知外部（页面据此决定要不要触发自动标记）
	closed.emit(hit_btn)


# 把气泡转挂到父节点，让它播完消失动画再自毁
func _detach_and_dismiss_toast() -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	var new_parent: Node = get_parent()
	if new_parent != null and _toast.get_parent() == self:
		_toast.reparent(new_parent, true)

	if not _toast.dismissed.is_connected(_toast.queue_free):
		_toast.dismissed.connect(_toast.queue_free)
	_toast.dismiss()
	_toast = null


# 退出场景树时兜底还原 z 值
func _exit_tree() -> void:
	_restore_z()
