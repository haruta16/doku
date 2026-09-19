# 草稿功能新手引导：全屏遮罩 + 假按钮 + 气泡说明，点假按钮算命中，点别处算关闭
extends CanvasLayer
class_name DraftOnboardingTooltip

# ---- 对外信号 ----
signal hit_draft_btn # 点了草稿按钮
signal closed # 点了别处关闭

# ---- 子节点引用 ----
@onready var _mask: ColorRect = $MaskRect # 全屏遮罩
@onready var _fake_btn: Control = $FakeBtn # 替代真按钮的假按钮
@onready var _control: Control = $Control # 气泡整体容器
@onready var _bubble_panel: Panel = $Control/BubblePanel # 气泡底板
@onready var _bubble_label: Label = $Control/BubblePanel/BubbleLabel # 气泡文案
@onready var _arrow: TextureRect = $Control/Arrow # 指向按钮的箭头
@onready var _anim: AnimationPlayer = $AnimationPlayer # 动画播放器

# ---- 动画与布局常量 ----
const _ANIM_NAME: StringName = &"BubblePanel" # 气泡动画名

const _DISAPPEAR_MARKER: StringName = &"Disappear" # 退场标记名

const _BLOCK_DURATION_SEC: float = 0.5 # 关闭前的防误触时长（秒）

const _ARROW_TO_BTN_GAP: float = -3.0 # 箭头与按钮的间距（像素，负数表示重叠）

const _BUBBLE_PAD_H: float = 45.0 # 气泡左右内边距（像素）
const _BUBBLE_PAD_V: float = 20.0 # 气泡上下内边距（像素）

const _ARROW_PANEL_OVERLAP: float = 1.0 # 箭头与气泡的重叠量（像素）

# ---- 运行时状态 ----
var _draft_btn_rect: Rect2 = Rect2() # 草稿按钮的屏幕矩形，用来判断点击是否命中
var _block_until_ms: int = 0 # 早于这个时间戳的点击不响应（毫秒）
var _closing: bool = false # 是否正在关闭


# ================= 生命周期 =================
# 进树：记录防误触截止时间，并给遮罩和气泡接上点击
func _ready() -> void:
	_block_until_ms = Time.get_ticks_msec() + int(_BLOCK_DURATION_SEC * 1000)
	_mask.gui_input.connect(_on_mask_input)
	_bubble_panel.gui_input.connect(_on_mask_input)


# ================= 显示与布局 =================
# 按草稿按钮的位置摆好假按钮与气泡，然后播入场动画
func show_at(draft_btn_global_rect: Rect2) -> void:
	_draft_btn_rect = draft_btn_global_rect
	var btn_pos: Vector2 = draft_btn_global_rect.position
	var btn_size: Vector2 = draft_btn_global_rect.size

	# 假按钮缩放到与真按钮同尺寸并对齐
	if _fake_btn.size.x > 0.0 and _fake_btn.size.y > 0.0:
		_fake_btn.scale = btn_size / _fake_btn.size
	_fake_btn.position = btn_pos

	_layout_bubble()

	# 让箭头尖对准按钮上沿
	var arrow_bottom_center_local: Vector2 = (
		_arrow.position + Vector2(_arrow.size.x / 2.0, _arrow.size.y)
	)

	var arrow_bottom_center_global: Vector2 = Vector2(
		btn_pos.x + btn_size.x / 2.0,
		btn_pos.y - _ARROW_TO_BTN_GAP,
	)
	_control.position = arrow_bottom_center_global - arrow_bottom_center_local

	# 播到消失标记为止
	_anim.play_section_with_markers(_ANIM_NAME, &"", _DISAPPEAR_MARKER)


# 按文案实际大小重排气泡，并算出箭头与气泡的相对位置
func _layout_bubble() -> void:
	var txt_size: Vector2 = _bubble_label.get_minimum_size()
	var panel_size: Vector2 = Vector2(
		txt_size.x + _BUBBLE_PAD_H * 2.0,
		txt_size.y + _BUBBLE_PAD_V * 2.0,
	)

	# 气泡尺寸由文案决定
	_bubble_panel.custom_minimum_size = Vector2.ZERO
	_bubble_panel.position = Vector2.ZERO
	_bubble_panel.size = panel_size

	# 文案四周留白
	_bubble_label.offset_left = _BUBBLE_PAD_H
	_bubble_label.offset_top = _BUBBLE_PAD_V
	_bubble_label.offset_right = -_BUBBLE_PAD_H
	_bubble_label.offset_bottom = -_BUBBLE_PAD_V
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 箭头贴在气泡底边
	_arrow.position.y = panel_size.y - _ARROW_PANEL_OVERLAP

	_control.size = Vector2(panel_size.x, _arrow.position.y + _arrow.size.y)
	# 整体高度 = 气泡高 + 露出的箭头
	if _control.size.x > 0.0 and _control.size.y > 0.0:
		var arrow_bottom_center_local: Vector2 = (
			_arrow.position + Vector2(_arrow.size.x / 2.0, _arrow.size.y)
		)
		# 缩放轴心落在箭头尖上
		_control.pivot_offset_ratio = arrow_bottom_center_local / _control.size


# ================= 输入与关闭 =================
# 遮罩/气泡被点击：判断点是否落在草稿按钮上
func _on_mask_input(event: InputEvent) -> void:
	if _closing:
		return
	# 只认鼠标左键按下
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# 防误触时间内不响应
	if Time.get_ticks_msec() < _block_until_ms:
		return

	# 命中草稿按钮 → hit_draft_btn，否则只算关闭
	if _draft_btn_rect.has_point(mb.position):
		hit_draft_btn.emit()
	else:
		closed.emit()
	_close()


# 关闭：标记引导已看过，播退场动画后自毁
func _close() -> void:
	if _closing:
		return
	_closing = true
	# 写入「已展示」标记（会写存档）
	GameState.mark_draft_onboarding_shown()

	# 等退场动画播完再释放自己
	_anim.play_section_with_markers(_ANIM_NAME, _DISAPPEAR_MARKER, &"")
	await _anim.animation_finished
	queue_free()
