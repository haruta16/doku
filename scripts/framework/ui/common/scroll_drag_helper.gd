## 滚动手势辅助：在拖拽、惯性和边缘回弹间切换，统一同步内容位置与按下状态。
## 约定 ScrollContainer 的第一个子节点为内容 Control；纵向支持惯性/弹性，横向只跟随拖拽。
class_name ScrollDragHelper
extends Node

## 宿主提供遮罩查询；独立框架消费者可留空，不依赖任何产品 Autoload。
static var _input_gate: Callable # 全类型共享的宿主查询，不持有每个助手各自的策略

## 配置所有助手共享的遮罩查询：接收 ScrollContainer，返回 true 表示应拒绝手势；空 Callable 表示不做此检查。
## 这是静态单槽，后一次配置覆盖前一次；多管理器场景需由宿主协调归属。
static func configure_input_gate(query: Callable = Callable()) -> void:
	_input_gate = query


const _DRAG_THRESHOLD: float = 12.0 # 位移超过 12 像素才判定成拖拽（否则算点击）
const _MOTION_WINDOW_SEC: float = 0.06 # 只统计最近 0.06 秒的位移来估算松手速度

signal content_shifted # 内容实际纵向位置已变化，虚拟列表据此更新可见范围

signal interaction_cancelled # 拖拽或打断惯性后的释放被吞掉，用于取消外部点击表现

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
var _recent_motions: Array = [] # 最近移动事件的 {delta_y, dt} 样本，位移为像素、dt 为处理帧时长（秒）

var _scroll: ScrollContainer # 被增强的滚动容器
var _is_pressing: bool = false # 指针是否按住
var _drag_active: bool = false # 是否已越过阈值进入拖拽
var _press_pos: Vector2 = Vector2.ZERO # 按下时的坐标，用来算阈值
var _last_pos: Vector2 = Vector2.ZERO # 上一次移动的坐标，用来算帧位移
var _active_pointer_index: int = -1 # 正在追踪的指针号：触摸=手指 index，鼠标=-2，-1=无

var _suppressed_release_pointer_index: int = -1 # 已取消手势但尚未收到释放的指针；-1 表示无待吞事件


## 停止拖拽、惯性与回弹；若手指仍按着，记住其释放事件并取消按钮按压，避免回收后误触新单元。
func stop_motion() -> void:
	# 取消可能发生在列表回收单元时；手指尚未抬起，后续 release 仍须截住。
	if _is_pressing and _active_pointer_index != -1:
		_suppressed_release_pointer_index = _active_pointer_index
		_cancel_pressed_buttons(_scroll)
	_reset_all()


## 容器重新排序后校正 Content 的纵向位置，使滚动条位置和额外越界量重新一致。
func synchronize_content_position() -> void:
	if not is_instance_valid(_scroll) or _scroll.get_child_count() == 0:
		return
	var content: Control = _scroll.get_child(0) as Control
	if (
		content == null
		or is_equal_approx(content.position.y, -float(_scroll.scroll_vertical) - _overscroll)
	):
		return
	_apply_overscroll_visual()


## 取消指定子树中的瞬时按钮按压；确实取消了按钮且仍在追踪指针时，结束本次拖拽并吞掉迟来的释放。
func cancel_pressed_interaction(root: Control) -> void:
	if not is_instance_valid(root):
		return
	var cancelled: bool = _cancel_pressed_buttons(root)
	if not cancelled or not _is_pressing:
		return
	_suppressed_release_pointer_index = _active_pointer_index
	_is_pressing = false
	_drag_active = false
	_active_pointer_index = -1
	_recent_motions.clear()
	_consumed_drift_release = false
	if _state == State.PRESSING or _state == State.DRAGGING:
		_state = State.IDLE


# ================= 挂载 =================
## 给 ScrollContainer 挂一个助手（已存在就复用并更新参数），返回助手实例
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


## 进树：容器隐藏时清状态，并关掉 _process（有动画时才开）
func _ready() -> void:
	# 容器一旦不可见就要把拖拽 / 惯性状态清干净，否则再显示时会残留
	if (
		_scroll != null
		and not _scroll.visibility_changed.is_connected(_on_scroll_visibility_changed)
	):
		_scroll.visibility_changed.connect(_on_scroll_visibility_changed)
	set_process(false)


## 节点被删时兜底清状态，避免补间回调碰到已释放的对象
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_reset_all()


# ================= 惯性滑行 =================
## 进入惯性滑行；容器滚不动时直接不进入
func _start_drift() -> void:
	if _scroll == null or _max_scroll() <= 0:
		_stop_drift()
		return
	_state = State.DRIFTING
	set_process(true)


## 结束惯性：清零速度并关 _process
func _stop_drift() -> void:
	_state = State.IDLE
	_velocity = Vector2.ZERO
	set_process(false)


## 每帧按状态分派：只有 DRIFTING / ELASTIC 需要跑
func _process(delta: float) -> void:
	match _state:
		State.DRIFTING:
			_tick_drift(delta)
		State.ELASTIC:
			_tick_elastic(delta)


## 用速度积分更新纵向滚动；越界时转入弹性态或直接停边，范围内按时间衰减速度。
func _tick_drift(delta: float) -> void:
	var new_y: float = float(_scroll.scroll_vertical) + _velocity.y * delta
	var max_y: float = float(_max_scroll())

	var elastic_off: bool = elastic_max_overscroll <= 0.0
	if new_y < 0.0:
		if elastic_off:
			_scroll.scroll_vertical = 0
			_overscroll = 0.0
			_apply_overscroll_visual()
			_stop_drift()
			return
		_enter_elastic(new_y)
		return
	if new_y > max_y:
		if elastic_off:
			_scroll.scroll_vertical = int(max_y)
			_overscroll = 0.0
			_apply_overscroll_visual()
			_stop_drift()
			return
		_enter_elastic(new_y - max_y)
		return

	_scroll.scroll_vertical = int(new_y)
	_apply_overscroll_visual()
	# friction 表示按 60 Hz 计的衰减系数；指数按实际 delta 换算，避免帧率不同导致刹车强度不同。
	_velocity.y *= pow(friction, delta * 60.0)
	if absf(_velocity.y) < min_velocity:
		_stop_drift()


## 进入越界态：越界量夹在上下限内，滚动条贴边，之后靠手动位移做视觉
func _enter_elastic(out_of_bounds: float) -> void:
	_state = State.ELASTIC
	_overscroll = clampf(out_of_bounds, -elastic_max_overscroll, elastic_max_overscroll) # out_of_bounds 是「超出边界多少」，夹紧后最多拉 elastic_max_overscroll 像素

	if _overscroll < 0.0:
		_scroll.scroll_vertical = 0
	else:
		_scroll.scroll_vertical = _max_scroll()
	_apply_overscroll_visual()
	set_process(true)


## 越界每帧：速度没耗尽就继续拉大越界量（带额外阻力），耗尽后交给回弹补间
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


## 起一个补间把越界量拉回 0；补间结束回到 IDLE 并关 _process
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


## 把手指越界距离压缩成渐近上限的橡皮筋位移，保留方向；关闭弹性时返回 0。
func _rubber_band(excess: float) -> float:
	var d: float = elastic_max_overscroll
	if d <= 0.0:
		return 0.0
	var a: float = absf(excess)
	# 距离越大，新增位移越小并渐近 d；不是越界后硬夹到同一个位置。
	return signf(excess) * (1.0 - 1.0 / (a / d + 1.0)) * d


## 回弹补间的回调：更新越界量并刷新视觉
func _set_overscroll(v: float) -> void:
	_overscroll = v
	_apply_overscroll_visual()


## 以滚动条偏移叠加额外越界量写入第一个 Content 子节点，并发送 content_shifted 供虚拟列表同步。
func _apply_overscroll_visual() -> void:
	if _scroll == null or _scroll.get_child_count() == 0:
		return
	var content := _scroll.get_child(0) as Control
	if content == null:
		return

	content.position.y = -float(_scroll.scroll_vertical) - _overscroll

	content_shifted.emit()


## 容器不可见时重置（隐藏后不该继续滑）
func _on_scroll_visibility_changed() -> void:
	if _scroll != null and not _scroll.is_visible_in_tree():
		_reset_all()


## 全量重置：状态 / 速度 / 越界 / 补间 / 指针追踪全部清空
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


## 最大可滚动量 = 纵向滚动条 max - page，不可滚动时为 0
func _max_scroll() -> int:
	if _scroll == null:
		return 0
	var v_scroll: VScrollBar = _scroll.get_v_scroll_bar()
	if v_scroll == null:
		return 0
	return int(maxf(0.0, v_scroll.get_max() - v_scroll.get_page()))


## 先吞掉已取消手势的释放，再检查容器可见性与遮罩，最后统一分派触摸和鼠标的按下/移动。
func _input(event: InputEvent) -> void:
	# 待吞释放先于可见性/遮罩检查：即使列表已隐藏或条目已换绑，也不能把旧 release 留给新按钮。
	if _suppressed_release_pointer_index != -1:
		var released_pointer: int = -1
		if event is InputEventScreenTouch and not event.pressed:
			released_pointer = event.index
		elif (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed
		):
			released_pointer = -2
		if released_pointer == _suppressed_release_pointer_index:
			_suppressed_release_pointer_index = -1
			get_viewport().set_input_as_handled()
			return
	if _scroll == null or not _scroll.is_visible_in_tree():
		_reset()
		return

	if _scroll.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_reset()
		return

	# 框架只问宿主是否被遮罩挡住，不认识产品 UIManager；未配置时跳过这一额外保护。
	if _input_gate.is_valid() and bool(_input_gate.call(_scroll)):
		_reset()
		return

	if event is InputEventScreenTouch:
		_handle_press(event.position, event.pressed, event.index)
	elif event is InputEventScreenDrag:
		if _active_pointer_index == event.index:
			_handle_motion(event.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_press(mb.position, mb.pressed, -2)
	elif event is InputEventMouseMotion:
		if _active_pointer_index == -2 and _is_pressing:
			_handle_motion(event.position)


## 按下时锁定一个指针并打断旧运动；释放时按越界量、拖拽速度决定回弹、惯性或普通结束。
func _handle_press(pos: Vector2, pressed: bool, pointer_index: int) -> void:
	if pressed:
		if _suppressed_release_pointer_index != -1:
			return
		# 只跟踪一个指针；第二根手指不能改写第一根的起点或触发它的释放。
		if _is_pressing and _active_pointer_index != pointer_index:
			return
		var rect: Rect2 = _scroll.get_global_rect()
		if not rect.has_point(pos):
			return

		# 点住正在滑动的列表通常意图是刹车，这次释放要消费掉，不能顺带点击底下按钮。
		var was_in_motion: bool = _state == State.DRIFTING or _state == State.ELASTIC
		if was_in_motion:
			_velocity = Vector2.ZERO
			if _bounce_tween != null:
				_bounce_tween.kill()
				_bounce_tween = null
			if _state == State.ELASTIC:
				_overscroll = 0.0
				_apply_overscroll_visual()
			_consumed_drift_release = true
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

		var was_dragging: bool = _drag_active
		var should_swallow: bool = was_dragging or _consumed_drift_release
		_consumed_drift_release = false

		if should_swallow:
			_cancel_pressed_buttons(_scroll)

		# 已经越界时优先回弹，不把拖动样本再转换成一次新的惯性滑行。
		if absf(_overscroll) > 0.5:
			_is_pressing = false
			_drag_active = false
			_active_pointer_index = -1
			_recent_motions.clear()
			_velocity = Vector2.ZERO
			_state = State.ELASTIC
			set_process(false)
			_start_bounce_back()
			if should_swallow:
				get_viewport().set_input_as_handled()
				interaction_cancelled.emit()
			return

		var release_v: float = _calc_release_velocity()
		var should_drift: bool = (
			with_inertia and was_dragging and absf(release_v) > min_velocity * 2.0
		)
		if should_drift:
			_velocity = Vector2(0.0, release_v)
			_is_pressing = false
			_drag_active = false
			_active_pointer_index = -1
			_recent_motions.clear()
			_start_drift()
		else:
			_reset()

		if should_swallow:
			get_viewport().set_input_as_handled()
			interaction_cancelled.emit()


## 超过阈值后从点击转为拖拽：更新滚动/橡皮筋位置，取消按钮按压，并积累松手速度样本。
func _handle_motion(pos: Vector2) -> void:
	if not _is_pressing:
		return
	var delta: Vector2 = pos - _last_pos
	# 阈值以内保留点击语义；一旦进入拖拽就取消按钮按压，松手不再触发点击。
	if not _drag_active:
		if (pos - _press_pos).length() > _DRAG_THRESHOLD:
			_drag_active = true
			_state = State.DRAGGING
			_cancel_pressed_buttons(_scroll)
	if _drag_active:
		var v_enabled: bool = _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		var h_enabled: bool = _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		if v_enabled:
			var rubber_on: bool = with_inertia and elastic_max_overscroll > 0.0
			var max_y: float = float(_max_scroll())
			# 逻辑滚动条始终留在有效范围，越界部分单独存在 _overscroll，由 Content 位移呈现。
			var virtual: float = float(_scroll.scroll_vertical) + _overscroll - delta.y
			if rubber_on and virtual < 0.0:
				_scroll.scroll_vertical = 0
				_overscroll = _rubber_band(virtual)
			elif rubber_on and virtual > max_y:
				_scroll.scroll_vertical = int(max_y)
				_overscroll = _rubber_band(virtual - max_y)
			else:
				_scroll.scroll_vertical = int(clampf(virtual, 0.0, max_y))
				_overscroll = 0.0
		if h_enabled:
			_scroll.scroll_horizontal = int(_scroll.scroll_horizontal - delta.x)
		if v_enabled:
			_apply_overscroll_visual()

		# 按移动事件记录位移与当前帧时长；没有移动事件的停顿不会主动插入零速样本。
		var dt: float = get_process_delta_time()
		if dt > 0.0:
			_recent_motions.append({"delta_y": delta.y, "dt": dt})
			_trim_recent_motions()
		get_viewport().set_input_as_handled()
	_last_pos = pos


## 轻量重置：清掉指针追踪并回到 IDLE；不清速度/越界值，也不 kill 回弹补间，完整停止用 stop_motion。
func _reset() -> void:
	_is_pressing = false
	_drag_active = false
	_active_pointer_index = -1
	_state = State.IDLE
	_recent_motions.clear()


## 按样本记录的 dt 累计裁剪到 _MOTION_WINDOW_SEC 附近，至少保留一条；不是按事件墙钟时间自动过期。
func _trim_recent_motions() -> void:
	var total_dt: float = 0.0
	for m in _recent_motions:
		total_dt += m.dt

	while total_dt > _MOTION_WINDOW_SEC and _recent_motions.size() > 1:
		var oldest = _recent_motions.pop_front()
		total_dt -= oldest.dt


## 用样本的平均速度估算松手速度；取负号是因为屏幕位移方向与滚动方向相反
func _calc_release_velocity() -> float:
	var total_dy: float = 0.0
	var total_dt: float = 0.0
	for m in _recent_motions:
		total_dy += m.delta_y
		total_dt += m.dt
	if total_dt < 0.001:
		return 0.0

	return -total_dy / total_dt


## 递归取消正在按下的非切换按钮，返回是否取消过；短暂禁用再恢复，不发业务点击也不改 toggle 选择态。
func _cancel_pressed_buttons(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var cancelled: bool = false
	if node is BaseButton:
		var btn := node as BaseButton
		# toggle 按钮的 pressed 是持久选择状态，不能当成一次尚未结束的手势强制清掉。
		if btn.button_pressed and not btn.toggle_mode:
			var was_disabled: bool = btn.disabled
			btn.disabled = true
			btn.disabled = was_disabled
			cancelled = true
	var children: Array[Node] = node.get_children()
	for child in children:
		cancelled = _cancel_pressed_buttons(child) or cancelled
	return cancelled
