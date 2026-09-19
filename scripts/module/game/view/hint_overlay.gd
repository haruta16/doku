# 提示浮层：展示策略文案与操作按钮，按 AB 流程切换按钮组合，并贴着棋盘上下摆放
class_name HintOverlay
extends CanvasLayer

# ---- 布局参数 ----
const SPACING_TO_BOARD: float = 15.0 # 横幅/按钮组与棋盘之间的间距（像素）

# ---- 子节点引用 ----
@onready var _overlay: ColorRect = $Overlay # 半透明遮罩
@onready var _banner: Panel = $Banner # 文案横幅
@onready var _btn_group: VBoxContainer = $BtnGroup # 底部按钮组
@onready var _strategy_label: Label = $Banner/StrategyLabel # 策略名标签（仅调试可见）
@onready var _desc_label: RichTextLabel = $Banner/DescLabel # 文案
@onready var _detail_btn: Button = $Banner/DetailBtn # 详情按钮
@onready var _dismiss_btn: Control = $BtnGroup/DismissBtn # 忽略按钮
@onready var _apply_btn: Control = $BtnGroup/ApplyBtn # 应用按钮
@onready var _cancel_btn: Control = $BtnGroup/CancelBtn # 取消按钮
@onready var _next_btn: Control = $BtnGroup/NextBtn # 下一步按钮
@onready var _close_btn: TextureButton = $Banner/CloseBtn # 关闭按钮

# ---- 对外信号（由页面连接） ----
signal hint_applied # 应用：让页面执行提示
signal hint_dismissed # 忽略/取消/关闭：只关浮层
signal hint_detail_requested # 请求更多说明

# ---- 运行时状态 ----
var _hint: Dictionary = {} # 当前提示数据

var _next_step_revealed: bool = false # 是否已点过「下一步」


# ================= 生命周期 =================
# 进树：给详情按钮绑按压缩放反馈
func _ready() -> void:
	UIHelper.bind_press_release_scale(_detail_btn)


# ================= 显示流程 =================
# 显示提示：先按 strategy 定文案，再按 AB 流程定按钮组合
func show_hint(hint: Dictionary) -> void:
	# 记下这份数据，按钮回调与调试都要用
	_hint = hint
	var strategy: String = hint.get("strategy", "")
	match strategy:
		# R1~R5 各有一套固定文案，description 可覆盖
		"R1_mark":
			_strategy_label.text = "R1"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_R1_MARK")))
		"R2":
			_strategy_label.text = "R2"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_REGION_CONSTRAINT")))
		"R3":
			_strategy_label.text = "R3"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_SET_LOCKING")))
		"R4":
			_strategy_label.text = "R4"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_LARGE_SET_LOCKING")))
		"R4_chain":
			_strategy_label.text = "R4"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_CONTRADICTION")))
		"R5_chain":
			_strategy_label.text = "R5"
			_desc_label.clear()
			_desc_label.append_text(hint.get("description", tr("HINT_CONTRADICTION")))
		_:
			# 未知策略：按单位类型拼「这个单位只剩一格」的文案
			_strategy_label.text = "R1"
			# 页面给了 description 就优先用
			var unit_type: String = hint.get("unit_type", "")
			var desc_override: String = hint.get("description", "")
			if desc_override != "":
				_desc_label.clear()
				_desc_label.append_text(desc_override)
			# 整行类型：提示交叉格
			elif unit_type == "full_line":
				_desc_label.clear()
				_desc_label.append_text(tr("HINT_INTERSECTION"))
			else:
				# 否则先取单位名称
				var unit_name: String
				match unit_type:
					"row":
						unit_name = tr("HINT_ROW") % (hint.get("unit_index", 0) + 1)
					"col":
						unit_name = tr("HINT_COL") % (hint.get("unit_index", 0) + 1)
					"region":
						unit_name = tr("HINT_COLOR_REGION")
					_:
						unit_name = tr("HINT_UNIT_ROW_COL_REGION")
				_desc_label.clear()
				_desc_label.append_text(tr("HINT_ONLY_ONE_CELL") % unit_name)

	# 只有链式策略才有后续步骤
	var _chain_d: Dictionary = hint.get("chain", {})
	var has_steps := (
		(strategy == "R4_chain" or strategy == "R5_chain")
		and not _chain_d.is_empty()
		and (_chain_d.get("steps", []) as Array).size() > 0
	)
	# 每次显示都重置「已展开后续步骤」
	_next_step_revealed = false
	# V1：新版提示流程；V2：带关闭按钮的流程
	var _is_v1: bool = ABTestManager.hint_ue.is_new_hint_flow()
	var _is_v2: bool = ABTestManager.hint_ue.is_close_btn_flow()
	if _is_v1 or _is_v2:
		# 新流程一律先隐藏老按钮
		_detail_btn.visible = false
		_dismiss_btn.visible = false
		_cancel_btn.visible = false
		_close_btn.visible = false
		# 有后续步骤 → 只给「下一步」
		if has_steps:
			_apply_btn.visible = false
			_next_btn.visible = true
			_close_btn.visible = _is_v2
		else:
			# 没有后续步骤 → 直接可应用
			_apply_btn.visible = true
			_next_btn.visible = false
			# V2 用关闭按钮，否则用取消按钮
			if _is_v2:
				_close_btn.visible = true
			else:
				_cancel_btn.visible = true
	# 老流程：应用按钮常驻，链式步骤才给详情
	else:
		_apply_btn.visible = true
		_detail_btn.visible = has_steps
		_dismiss_btn.visible = false
		_cancel_btn.visible = false
		_next_btn.visible = false
		_close_btn.visible = false

	# 调试模式显示策略名，文案区域随之让位
	var _debug: bool = GameState.is_debug_mode()
	_strategy_label.visible = _debug
	var _left: float = 210.0 if _debug else 50.0

	var _right: float = (_detail_btn.position.x - 20.0) if _detail_btn.visible else 850.0
	_desc_label.offset_left = _left
	_desc_label.offset_right = _right
	_desc_label.offset_top = 0.0
	_desc_label.offset_bottom = 190.0

	# 文案垂直居中（等 RichTextLabel 量完高度）
	call_deferred("_center_desc_label")
	visible = true
	# 遮罩从全透明淡入
	_overlay.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.75, 0.3)

	# 贴到棋盘上（等布局完成）
	call_deferred("_align_to_board")


# ================= 按钮回调 =================
# 应用按钮：关掉浮层，通知页面执行这条提示
func _on_apply_btn_pressed() -> void:
	visible = false
	hint_applied.emit()


# 忽略按钮：关掉浮层，通知页面
func _on_dismiss_btn_pressed() -> void:
	visible = false
	hint_dismissed.emit()


# 取消按钮：同忽略
func _on_cancel_btn_pressed() -> void:
	visible = false
	hint_dismissed.emit()


# 关闭按钮：同忽略
func _on_close_btn_pressed() -> void:
	visible = false
	hint_dismissed.emit()


# 下一步按钮：展开后续步骤并请求页面补充文案
func _on_next_btn_pressed() -> void:
	# 标记已展开，按钮位换成应用
	_next_step_revealed = true
	_next_btn.visible = false
	_apply_btn.visible = true
	# V2 流程用关闭按钮，否则用取消
	if ABTestManager.hint_ue.is_close_btn_flow():
		_close_btn.visible = true
	else:
		_cancel_btn.visible = true

	hint_detail_requested.emit()

	# 文案变了，重新贴一次位置
	call_deferred("_align_to_board")


# 详情按钮：拉宽文案区并请求完整说明
func _on_detail_btn_pressed() -> void:
	# 详情按钮用完即隐
	_detail_btn.visible = false
	_desc_label.offset_right = 850.0
	hint_detail_requested.emit()


# ================= 文案与布局 =================
# 把文案在 190 像素高的区域内垂直居中
func _center_desc_label() -> void:
	var content_h: float = _desc_label.get_content_height()
	var total_h: float = 190.0
	var top: float = maxf(0.0, (total_h - content_h) / 2.0)
	_desc_label.offset_top = top
	_desc_label.offset_bottom = top + content_h


# 外部更新文案内容
func update_desc(text: String) -> void:
	_desc_label.clear()
	_desc_label.append_text(text)


# 显示忽略按钮（老流程才有）
func show_dismiss_btn() -> void:
	if ABTestManager.hint_ue.is_any_new_flow():
		# 新流程不提供忽略按钮
		pass
	else:
		_dismiss_btn.visible = true


# 把横幅贴到棋盘上方、按钮组贴到棋盘下方
func _align_to_board() -> void:
	var board := _find_board()
	if board == null:
		return
	var board_top: float = board.global_position.y
	var board_bottom: float = board_top + board.size.y * board.scale.y
	var viewport_h: float = get_viewport().get_visible_rect().size.y

	var banner_h: float = _banner.size.y
	# 横幅底边压在棋盘上沿之上
	_banner.offset_bottom = board_top - SPACING_TO_BOARD
	_banner.offset_top = _banner.offset_bottom - banner_h

	var btn_h: float = _btn_group.size.y
	# 按钮组顶边压在棋盘下沿之下
	_btn_group.offset_top = (board_bottom + SPACING_TO_BOARD) - viewport_h
	_btn_group.offset_bottom = _btn_group.offset_top + btn_h


# 找到棋盘节点（页面结构固定）
func _find_board() -> Control:
	var page_root := get_parent()
	if page_root == null:
		return null
	return page_root.get_node_or_null("VBoxContainer/BoardContainer/BoardView") as Control
