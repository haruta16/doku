# 滚动容器拖拽增强：手指按住拖动 + 松手惯性滑行 + 越界橡皮筋回弹；由 attach 挂到 ScrollContainer 下当一个子节点
class_name ScrollDragHelper
extends Node

const _DRAG_THRESHOLD: float = 12.0 # 位移超过 12 像素才判定成拖拽（否则算点击）
const _MOTION_WINDOW_SEC: float = 0.06 # 只统计最近 0.06 秒的位移来估算松手速度

@export var with_inertia: bool = false # 是否开启松手惯性；false 则松手即停
@export var friction: float = 0.95 # 速度衰减系数（数值越小刹得越快）
@export var min_velocity: float = 30.0 # 速度低于此值（像素/秒）就停止滑行
@export var elastic_max_overscroll: float = 120.0 # 越界最多能拉出多少像素（橡皮筋长度上限）
@export var elastic_resist: float = 0.5 # 越界阶段叠加的额外阻力系数（乘在 friction 上）
@export var elastic_bounce_back_sec: float = 0.28 # 回弹补间时长（单位：秒）

enum State { IDLE, PRESSING, DRAGGING, DRIFTING, ELASTIC } # 状态：IDLE 静止 / PRESSING 按下未过阈值 / DRAGGING 拖拽中 / DRIFTING 惯性滑行 / ELASTIC 越界回弹
var _state: int = State.IDLE # 当前状态
var _velocity: Vector2 = Vector2.ZERO # 惯性速度（像素/秒），只用到 y 分量
var _overscroll: float = 0.0 # 当前越界量（像素）：正=底部越界，负=顶部越界
var _bounce_tween: Tween = null # 回弹补间；非 null 表示正在回弹
var _consumed_drift_release: bool = false # 本次按下打断了滑行：抬起时要吞掉事件，避免顺手误触按钮
var _recent_motions: Array = [] # 最近若干帧的 {delta_y, dt} 样本，用来算松手速度

var _scroll: ScrollContainer # 被增强的滚动容器
var _is_pressing: bool = false # 指针是否按住
var _drag_active: bool = false # 是否已越过阈值进入拖拽
var _press_pos: Vector2 = Vector2.ZERO # 按下时的坐标，用来算阈值
var _last_pos: Vector2 = Vector2.ZERO # 上一次移动的坐标，用来算帧位移
var _active_pointer_index: int = -1 # 正在追踪的指针号：触摸=手指 index，鼠标=-2，-1=无


# ================= 挂载 =================
# 给 ScrollContainer 挂一个助手（已存在就复用并更新参数），返回助手实例
static func attach(scroll: ScrollContainer, with_inertia: bool = false) -> ScrollDragHelper:
	if scroll == null:
		push_error("ScrollDragHelper.attach: scroll is null")
		return null

	for child in scroll.get_children():
		if child is ScrollDragHelper:
			var existing := child as ScrollDragHelper
			existing.with_inertia = with_inertia # 已有实例：只更新参数，不重复挂
			return existing
	var helper := ScrollDragHelper.new()
	helper.name = "_ScrollDragHelper"
	helper._scroll = scroll
	helper.with_inertia = with_inertia
	scroll.add_child(helper)
	return helper


# 进树：容器隐藏时清状态，并关掉 _process（有动画时才开）
func _ready() -> void:
	# 容器一旦不可见就要把拖拽 / 惯性状态清干净，否则再显示时会残留
	if (
		_scroll != null
		and not _scroll.visibility_changed.is_connected(_on_scroll_visibility_changed)
	):
		_scroll.visibility_changed.connect(_on_scroll_visibility_changed)
	set_process(false)


# 节点被删时兜底清状态，避免补间回调碰到已释放的对象
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_reset_all()


# ================= 惯性滑行 =================
# 进入惯性滑行；容器滚不动时直接不进入
func _start_drift() -> void:
	if _scroll == null or _max_scroll() <= 0:
		_stop_drift()
		return
	_state = State.DRIFTING
	set_process(true)


# 结束惯性：清零速度并关 _process
func _stop_drift() -> void:
	_state = State.IDLE
	_velocity = Vector2.ZERO
	set_process(false)


# 每帧按状态分派：只有 DRIFTING / ELASTIC 需要跑
func _process(delta: float) -> void:
	match _state:
		State.DRIFTING:
			_tick_drift(delta)
		State.ELASTIC:
			_tick_elastic(delta)


# 惯性每帧：按速度推进滚动位置；越界就转橡皮筋，速度按 friction 衰减到阈值以下停
func _tick_drift(delta: float) -> void:
	var new_y: float = float(_scroll.scroll_vertical) + _velocity.y * delta
	var max_y: float = float(_max_scroll())

	if new_y < 0.0: # 冲到顶部之外
		_enter_elastic(new_y)
		return
	if new_y > max_y: # 冲到底部之外
		_enter_elastic(new_y - max_y)
		return

	_scroll.scroll_vertical = int(new_y)
	_velocity.y *= pow(friction, delta * 60.0) # 乘 delta*60 让衰减与帧率无关（以 60fps 为基准）
	if absf(_velocity.y) < min_velocity:
		_stop_drift()


# 进入越界态：越界量夹在上下限内，滚动条贴边，之后靠手动位移做视觉
func _enter_elastic(out_of_bounds: float) -> void:
	_state = State.ELASTIC
	_overscroll = clampf(out_of_bounds, -elastic_max_overscroll, elastic_max_overscroll) # out_of_bounds 是「超出边界多少」，夹紧后最多拉 elastic_max_overscroll 像素

	if _overscroll < 0.0:
		_scroll.scroll_vertical = 0
	else:
		_scroll.scroll_vertical = _max_scroll()
	_apply_overscroll_visual()
	set_process(true)


# 越界每帧：速度没耗尽就继续拉大越界量（带额外阻力），耗尽后交给回弹补间
func _tick_elastic(delta: float) -> void:
	if absf(_velocity.y) > 0.1:
		_overscroll += _velocity.y * delta
		_overscroll = clampf(_overscroll, -elastic_max_overscroll, elastic_max_overscroll)
		_velocity.y *= pow(friction * elastic_resist, delta * 60.0)
		_apply_overscroll_visual()
		if absf(_velocity.y) < min_velocity:
			_velocity = Vector2.ZERO
			_start_bounce_back()

	elif _bounce_tween == null:
		_start_bounce_back()


# 起一个补间把越界量拉回 0；补间结束回到 IDLE 并关 _process
func _start_bounce_back() -> void:
	if _bounce_tween != null:
		_bounce_tween.kill()
	_bounce_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_method(_set_overscroll, _overscroll, 0.0, elastic_bounce_back_sec)
	_bounce_tween.finished.connect(
		func() -> void:
			_bounce_tween = null
			_state = State.IDLE
			set_process(false)
	)


# 回弹补间的回调：更新越界量并刷新视觉
func _set_overscroll(v: float) -> void:
	_overscroll = v
	_apply_overscroll_visual()


# 越界视觉：直接改容器第一个子节点的 y（ScrollContainer 自身无法越界）
func _apply_overscroll_visual() -> void:
	if _scroll == null or _scroll.get_child_count() == 0:
		return
	var content := _scroll.get_child(0) as Control
	if content == null:
		return

	content.position.y = -float(_scroll.scroll_vertical) - _overscroll # 内容 y = -滚动量 - 越界量，于是越界时内容被拉出边界


# 容器不可见时重置（隐藏后不该继续滑）
func _on_scroll_visibility_changed() -> void:
	if _scroll != null and not _scroll.is_visible_in_tree():
		_reset_all()


# 全量重置：状态 / 速度 / 越界 / 补间 / 指针追踪全部清空
func _reset_all() -> void:
	_state = State.IDLE
	_velocity = Vector2.ZERO
	_overscroll = 0.0
	if _bounce_tween != null:
		_bounce_tween.kill()
		_bounce_tween = null
	_apply_overscroll_visual()
	_consumed_drift_release = false
	_drag_active = false
	_is_pressing = false
	_active_pointer_index = -1
	_recent_motions.clear()
	set_process(false)


# 最大可滚动量 = 纵向滚动条 max - page，不可滚动时为 0
func _max_scroll() -> int:
	if _scroll == null:
		return 0
	var v_scroll: VScrollBar = _scroll.get_v_scroll_bar()
	if v_scroll == null:
		return 0
	return int(maxf(0.0, v_scroll.get_max() - v_scroll.get_page()))


# ================= 输入处理 =================
# 全局输入：触摸与鼠标两路，统一转成 _handle_press / _handle_motion
func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		_reset()
		return

	if event is InputEventScreenTouch: # 触摸：用 event.index 区分手指
		_handle_press(event.position, event.pressed, event.index)
	elif event is InputEventScreenDrag:
		if _active_pointer_index == event.index:
			_handle_motion(event.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_press(mb.position, mb.pressed, -2) # 鼠标统一用 -2 当指针号
	elif event is InputEventMouseMotion:
		if _active_pointer_index == -2 and _is_pressing: # 鼠标移动不带按下状态，要自己看 _is_pressing
			_handle_motion(event.position)


# 处理按下 / 抬起：按下开始追踪；抬起时决定是继续滑行还是直接收尾
func _handle_press(pos: Vector2, pressed: bool, pointer_index: int) -> void:
	if pressed:
		var rect: Rect2 = _scroll.get_global_rect()
		if not rect.has_point(pos): # 点在外面的按下不管
			return

		var was_in_motion: bool = _state == State.DRIFTING or _state == State.ELASTIC # 按住正在滑行的列表 = 立刻刹停
		if was_in_motion:
			_velocity = Vector2.ZERO
			if _bounce_tween != null:
				_bounce_tween.kill()
				_bounce_tween = null
			if _state == State.ELASTIC:
				_overscroll = 0.0
				_apply_overscroll_visual()
			_consumed_drift_release = true # 标记这次「刹车」需要吞掉后续抬起事件
			set_process(false)

		_state = State.PRESSING
		_is_pressing = true
		_drag_active = false
		_press_pos = pos
		_last_pos = pos
		_active_pointer_index = pointer_index
		_recent_motions.clear()
	else:
		if _active_pointer_index != pointer_index:
			return

		var was_dragging: bool = _drag_active # 拖过（超过阈值）就吞掉抬起，避免误触发按钮
		var should_swallow: bool = was_dragging or _consumed_drift_release
		_consumed_drift_release = false

		var release_v: float = _calc_release_velocity() # 松手瞬间估算出的甩动速度（像素/秒）
		var should_drift: bool = (
			with_inertia and was_dragging and absf(release_v) > min_velocity * 2.0
		)
		if should_drift: # 开了惯性、确实拖动过且速度超过 min_velocity 的 2 倍：进入滑行
			_velocity = Vector2(0.0, release_v)
			_is_pressing = false
			_drag_active = false
			_active_pointer_index = -1
			_recent_motions.clear()
			_start_drift()
		else:
			_reset()

		if should_swallow: # 吞掉事件，让下面的按钮收不到这次抬起
			get_viewport().set_input_as_handled()


# 处理移动：超过阈值才算拖拽；拖拽期间直接改滚动值并吞掉事件
func _handle_motion(pos: Vector2) -> void:
	if not _is_pressing:
		return
	var delta: Vector2 = pos - _last_pos
	if not _drag_active:
		if (pos - _press_pos).length() > _DRAG_THRESHOLD: # 越过阈值：升级为拖拽，并取消子按钮的按下态
			_drag_active = true
			_state = State.DRAGGING
			_cancel_pressed_buttons(_scroll)
	if _drag_active:
		var v_enabled: bool = _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		var h_enabled: bool = _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		if v_enabled:
			_scroll.scroll_vertical = int(_scroll.scroll_vertical - delta.y) # 手指往上滑（delta.y 为负）→ 滚动值变大
		if h_enabled:
			_scroll.scroll_horizontal = int(_scroll.scroll_horizontal - delta.x)

		var dt: float = get_process_delta_time()
		if dt > 0.0:
			_recent_motions.append({"delta_y": delta.y, "dt": dt}) # 记录本帧位移，供松手时算速度
			_trim_recent_motions()
		get_viewport().set_input_as_handled()
	_last_pos = pos


# 轻量重置：结束按下 / 拖拽，但不动惯性与越界
func _reset() -> void:
	_is_pressing = false
	_drag_active = false
	_active_pointer_index = -1
	_state = State.IDLE
	_recent_motions.clear()


# 只保留最近 _MOTION_WINDOW_SEC 内的样本，让速度反映「松手前」而不是整段拖动
func _trim_recent_motions() -> void:
	var total_dt: float = 0.0
	for m in _recent_motions:
		total_dt += m.dt

	while total_dt > _MOTION_WINDOW_SEC and _recent_motions.size() > 1:
		var oldest = _recent_motions.pop_front()
		total_dt -= oldest.dt


# 用样本的平均速度估算松手速度；取负号是因为屏幕位移方向与滚动方向相反
func _calc_release_velocity() -> float:
	var total_dy: float = 0.0
	var total_dt: float = 0.0
	for m in _recent_motions:
		total_dy += m.delta_y
		total_dt += m.dt
	if total_dt < 0.001:
		return 0.0

	return -total_dy / total_dt


# 递归取消子按钮的按下态（拖拽开始后按钮不该保持高亮）
func _cancel_pressed_buttons(node: Node) -> void:
	if node is BaseButton:
		var btn := node as BaseButton
		if btn.button_pressed and not btn.toggle_mode:
			btn.button_pressed = false
	for child in node.get_children():
		_cancel_pressed_buttons(child)
