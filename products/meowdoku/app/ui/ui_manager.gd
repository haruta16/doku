## Meowdoku 的 UI 装配入口：注册产品页面、资源绑定、声音、埋点和安全区规则。
## 窗口缓存、层级、遮罩与生命周期由独立的 UIWindowManager 负责。
extends UIWindowManager

var _tracker_observer: UITrackerObserver # 订阅框架窗口事件的产品埋点观察者；成员持有它以保持订阅期间存活。


## 装配产品注册表、声音和场景注入端口，再启动框架管理器；随后接入产品事件、安全区与调试监听。
func _ready() -> void:
	ScrollDragHelper.configure_input_gate(is_covered_by_mask)
	configure(UIRegistry.build_registry(), _play_ui_sound, _prepare_product_scene)
	super._ready()
	_tracker_observer = UITrackerObserver.new(events)
	events.window_created.connect(_on_product_window_created)
	events.window_shown.connect(_on_product_window_shown)
	events.window_hidden.connect(_on_product_window_hidden)
	get_viewport().size_changed.connect(_reapply_safe_area_all)
	_start_editor_layout_watcher()
	_start_canvas_watcher()
	_probe_enabled = OS.is_debug_build() and not OS.has_feature("rel")
	if _probe_enabled:
		get_window().window_input.connect(_on_window_input_probe)
	set_process_input(_probe_enabled)


## 把框架声明的声音提示映射到产品 SoundManager；框架本身不引用产品音频单例。
func _play_ui_sound(cue: StringName) -> void:
	match cue:
		UIBaseWindow.SOUND_BUTTON_CLICK:
			SoundManager.play(SoundManager.Kind.BTN_CLICK)
		UIBaseWindow.SOUND_WINDOW_OPEN:
			SoundManager.play(SoundManager.Kind.DLG_OPEN)


# ================= 刘海屏 / 安全区适配 =================
const _SAFE_TOP_GROUP: StringName = &"_safe_top" # 需要贴顶部安全区的节点分组名（.tscn 里挂 group）
const _SAFE_BOTTOM_GROUP: StringName = &"_safe_bottom" # 需要贴底部安全区的节点分组名
const _SAFE_BASELINE_META: StringName = &"_safe_area_baseline" # 一次记录两条边，双边适配也共用同一基线
const _COLLAPSE_WHEN_TOP_SAFE_GROUP: StringName = &"_collapse_when_top_safe" # 顶部有刘海时应该收起来的分组名
const _COLLAPSE_BASELINE_META: StringName = &"_collapse_when_top_safe_baseline" # 这类节点 可见性 / 最小高度 / 垂直尺寸标志 的基线 meta 键

## 只对这几个页面做安全区适配，弹窗等其它页面自己处理
const _SAFE_AREA_PAGES: Array[StringName] = [
	&"home",
	&"game",
	&"daily_game",
	&"win",
	&"fail",
	&"setting",
	&"bank", &"rank_activity_change", &"rank_activity_change_v2", &"rank_activity_page", &"subscription", &"rank_activity_offline",
]


## 系统安全区是屏幕像素，Control.offset 是父布局单位；不能直接相加。
func _apply_safe_area(page_name: String, node: Node) -> void:
	if _dbg_safe_on:
		var view: Rect2 = node.get_viewport().get_screen_transform() * node.get_viewport().get_visible_rect()
		_apply_safe_area_rect(page_name, node, Rect2(view.position + Vector2(0, _dbg_safe_top), Vector2(view.size.x, maxf(0.0, view.size.y - _dbg_safe_top - _dbg_safe_bottom))))
		return
	if not _is_mobile() and not _dbg_safe_touched:
		return
	_apply_safe_area_rect(page_name, node, Rect2(DisplayServer.get_display_safe_area()) if _is_mobile() else Rect2())


## 单独接收系统矩形，便于在桌面回归中验证真实的窗口/画布缩放。
## 分组应挂在可自行布局的 Control 上，Container 的直接孩子由容器控制，不应标记。
func _apply_safe_area_rect(page_name: String, node: Node, safe_screen_rect: Rect2) -> void:
	if not _SAFE_AREA_PAGES.has(StringName(page_name)):
		return
	var viewport: Viewport = node.get_viewport()
	var screen_rect: Rect2 = viewport.get_screen_transform() * viewport.get_visible_rect()
	var top_pixels: float = 0.0
	var bottom_pixels: float = 0.0
	if safe_screen_rect.has_area():
		# 已有窗口偏移或黑边先抵扣；超出可视区域的负 inset 不移动页面。
		top_pixels = clampf(safe_screen_rect.position.y - screen_rect.position.y, 0.0, screen_rect.size.y)
		bottom_pixels = clampf(screen_rect.end.y - safe_screen_rect.end.y, 0.0, screen_rect.size.y)
	# 零 inset 也要遍历：缓存页面必须恢复 offset 和顶部占位的基线。
	for n in node.find_children("*", "Control", true, false):
		var c := n as Control
		var use_top: bool = c.is_in_group(_SAFE_TOP_GROUP)
		var use_bottom: bool = c.is_in_group(_SAFE_BOTTOM_GROUP)
		if use_top or use_bottom:
			if not c.has_meta(_SAFE_BASELINE_META):
				c.set_meta(_SAFE_BASELINE_META, Vector2(c.offset_top, c.offset_bottom))
			var baseline: Vector2 = c.get_meta(_SAFE_BASELINE_META)
			var top_inset: float = _screen_y_to_layout(c, top_pixels) if use_top else 0.0
			var bottom_inset: float = _screen_y_to_layout(c, bottom_pixels) if use_bottom else 0.0
			if is_equal_approx(c.anchor_top, c.anchor_bottom):
				# 固定高度整体平移；上下拉伸的节点分别缩进两条边。
				c.offset_top = baseline.x + top_inset - bottom_inset
				c.offset_bottom = baseline.y + top_inset - bottom_inset
			else:
				c.offset_top = baseline.x + top_inset
				c.offset_bottom = baseline.y - bottom_inset
		# _collapse_when_top_safe 组：有刘海就直接隐藏并清零高度给内容腾地方，没刘海恢复基线
		if c.is_in_group(_COLLAPSE_WHEN_TOP_SAFE_GROUP):
			if not c.has_meta(_COLLAPSE_BASELINE_META):
				c.set_meta(
					_COLLAPSE_BASELINE_META,
					[c.visible, c.custom_minimum_size.y, c.size_flags_vertical]
				)
			var baseline: Array = c.get_meta(_COLLAPSE_BASELINE_META)
			if top_pixels > 0.0:
				c.visible = false
				c.custom_minimum_size.y = 0.0
				c.size_flags_vertical = 0
			else:
				c.visible = bool(baseline[0])
				c.custom_minimum_size.y = float(baseline[1])
				c.size_flags_vertical = int(baseline[2])


## 当前安全区布局沿屏幕竖轴排列。去除自身变换后，剩下的是 offset 所在父坐标系。
## 包括窗口拉伸、CanvasLayer 和父 Control 缩放，不受本节点的 pivot/scale 干扰。
func _screen_y_to_layout(control: Control, pixels: float) -> float:
	var local_transform: Transform2D = control.get_transform()
	if is_zero_approx(local_transform.determinant()):
		return 0.0
	var control_to_screen: Transform2D = (
		control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
	)
	var parent_to_screen: Transform2D = control_to_screen * local_transform.affine_inverse()
	if is_zero_approx(parent_to_screen.determinant()):
		return 0.0
	var screen_to_parent: Transform2D = parent_to_screen.affine_inverse()
	return screen_to_parent.y.y * pixels

var _guard_held_buttons: Array[BaseButton] = [] # 当前按下尚未释放的产品按钮；弹窗出现后用于取消跨层抬起。

var _guard_active: bool = false # 按住按钮期间新窗口出现时置 true，下一次抬起由管理器截获。

var _probe_enabled: bool = false # 仅调试且非 rel 构建启用点击路径诊断。

var _probe_pending: bool = false # 本帧已有一个待合并输出的按下事件。

var _probe_pos: Vector2 = Vector2.ZERO # 本轮诊断首次捕获的按下坐标（视口单位）。

var _probe_unhandled: bool = false # 按下事件是否到达 _unhandled_input；用来推断是否被上层消费。

var _probe_btn: String = "" # 本轮诊断中收到 button_down 的按钮名。

var _probe_via_win: bool = false # 本轮诊断是否由 Window.window_input 捕获过。

var _probe_via_input: bool = false # 本轮诊断是否由节点 _input 捕获过。

var _dbg_safe_on: bool = false # 使用调试安全区替代平台值。
var _dbg_safe_touched: bool = false # 桌面上曾显式设置过模拟安全区，清除后仍需恢复布局基线。
var _dbg_safe_top: float = 0.0 # 模拟顶部留白（屏幕像素）；非负。
var _dbg_safe_bottom: float = 0.0 # 模拟底部留白（屏幕像素）；非负。


## 设置模拟屏幕像素留白，立即重算设计画布与各缓存页面布局。
func debug_set_safe_inset(top: float, bottom: float) -> void:
	_dbg_safe_touched = true
	_dbg_safe_on = true
	_dbg_safe_top = maxf(0.0, top)
	_dbg_safe_bottom = maxf(0.0, bottom)

	apply_design_canvas()


## 停用模拟留白并重算布局；保留曾启用标记，让桌面缓存节点也能恢复原始基线。
func debug_clear_safe_inset() -> void:
	_dbg_safe_on = false
	_dbg_safe_top = 0.0
	_dbg_safe_bottom = 0.0
	apply_design_canvas()


const _LIVE_CFG_PATH := "user://resolution_picker_live.cfg" # 编辑器分辨率工具写入的本机配置路径，不属于游戏存档。
var _live_rev: int = -1 # 已处理的布局配置修订号，避免每次轮询重复调整窗口。
var _live_timer: Timer = null # 编辑器布局轮询 Timer，由本管理器作为父节点持有。
var _live_last_vh: float = -1.0 # 上次观察到的视口高度，用于识别画布尺寸变化。


## 仅编辑器环境创建定时器，读取分辨率工具写入的配置；游戏发布环境不启动。
func _start_editor_layout_watcher() -> void:
	if not OS.has_feature("editor"):
		return
	_live_timer = Timer.new()
	_live_timer.wait_time = 0.4
	_live_timer.autostart = true
	_live_timer.timeout.connect(_poll_live_layout)
	add_child(_live_timer)
	_poll_live_layout()


## 视口高度变化时先更新安全区；配置修订号变化时再应用窗口尺寸与模拟刘海。
func _poll_live_layout() -> void:
	var vh: float = get_viewport().get_visible_rect().size.y
	if not is_equal_approx(vh, _live_last_vh):
		_live_last_vh = vh
		_reapply_safe_area_all()

	var cfg := ConfigFile.new()
	if cfg.load(_LIVE_CFG_PATH) != OK:
		return
	var rev: int = int(cfg.get_value("live", "rev", 0))
	if rev == _live_rev:
		return
	_live_rev = rev
	var w: int = int(cfg.get_value("live", "w", 0))
	var h: int = int(cfg.get_value("live", "h", 0))
	if w > 0 and h > 0 and DisplayServer.window_get_size() != Vector2i(w, h):
		DisplayServer.window_set_size(Vector2i(w, h))
	var top: float = float(cfg.get_value("live", "notch_top", 0.0))
	var bottom: float = float(cfg.get_value("live", "notch_bottom", 0.0))
	if top > 0.0 or bottom > 0.0:
		debug_set_safe_inset(top, bottom)
	else:
		debug_clear_safe_inset()


## 遍历有效缓存窗口，先请求支持该接口的控件重算布局，再按原始基线更新安全边距。
func _reapply_safe_area_all() -> void:
	for ui_name in _cache:
		var win: UIFrameWindow = _cache[ui_name]
		if not is_instance_valid(win):
			continue
		for n in win.find_children("*", "Control", true, false):
			if n.has_method("debug_recompute"):
				n.call("debug_recompute")
		_apply_safe_area(String(ui_name), win)


const DESIGN_W: int = 1080 # 设计画布宽度（逻辑单位）。

const DESIGN_MIN_AVAIL_H: int = 1920 # 扣除安全留白后期望保留的设计高度基准（逻辑单位）。

const _CANVAS_POLL_SEC: float = 0.05 # 移动端启动时查询安全区的间隔（秒）。
const _CANVAS_POLL_TIMEOUT_SEC: float = 3.0 # 安全区查询最长等待时间（秒）；超时停止轮询。

var _canvas_poll_timer: Timer = null # 移动端短期安全区轮询器；成功或超时后释放。
var _canvas_poll_elapsed: float = 0.0 # 本轮已累计的轮询间隔（秒）。


## 按构建特征判断 Android/iOS 平台，供安全区与启动轮询分支共用。
func _is_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


## 根据窗口与安全区计算设计画布，设置缩放并重新应用各窗口安全边距。
func apply_design_canvas() -> void:
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var phys: Vector2 = _safe_insets_physical()
	var avail_h: float = float(win.y) - phys.x - phys.y
	var design_h: int = DESIGN_MIN_AVAIL_H
	if avail_h > 0.0:
		design_h = maxi(
			DESIGN_MIN_AVAIL_H, int(ceil(float(DESIGN_MIN_AVAIL_H) * float(win.y) / avail_h))
		)
	var root: Window = get_tree().root
	root.content_scale_size = Vector2i(DESIGN_W, design_h)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_reapply_safe_area_all()


## 移动端尚未拿到有效安全区时开始短期轮询，Timer 在暂停树中也继续运行。
func _start_canvas_watcher() -> void:
	if not _is_mobile() or is_safe_area_ready():
		return
	_canvas_poll_timer = Timer.new()
	_canvas_poll_timer.wait_time = _CANVAS_POLL_SEC
	_canvas_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas_poll_timer.timeout.connect(_on_canvas_poll)
	add_child(_canvas_poll_timer)
	_canvas_poll_timer.start()


## 拿到安全区后重算画布并结束轮询；到达时限则结束，避免常驻查询。
func _on_canvas_poll() -> void:
	_canvas_poll_elapsed += _CANVAS_POLL_SEC
	if is_safe_area_ready():
		apply_design_canvas()
		_stop_canvas_watcher()
		return
	if _canvas_poll_elapsed >= _CANVAS_POLL_TIMEOUT_SEC:
		_stop_canvas_watcher()


## 停止并排队释放安全区定时器；置空引用使重复清理安全。
func _stop_canvas_watcher() -> void:
	if _canvas_poll_timer != null and is_instance_valid(_canvas_poll_timer):
		_canvas_poll_timer.stop()
		_canvas_poll_timer.queue_free()
	_canvas_poll_timer = null


## 桌面直接视作已就绪；移动端要求系统安全区宽高均大于零。
func is_safe_area_ready() -> bool:
	if not _is_mobile():
		return true
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	return safe.size.x > 0 and safe.size.y > 0


## 返回顶部/底部留白，Vector2.x/y 分别表示上/下，单位为屏幕像素；无有效区域时返回零。
func _safe_insets_physical() -> Vector2:
	if _dbg_safe_on:
		return Vector2(_dbg_safe_top, _dbg_safe_bottom)
	if not _is_mobile() or not is_safe_area_ready():
		return Vector2.ZERO
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.y <= 0:
		return Vector2.ZERO

	return Vector2(
		maxf(0.0, float(safe.position.y)),
		maxf(0.0, float(win_size.y - (safe.position.y + safe.size.y))),
	)


## 供产品调用方读取顶部/底部留白；真实平台值换算到视口单位，调试模式直接返回模拟值。
func get_safe_insets() -> Vector2:
	if _dbg_safe_on:
		return Vector2(_dbg_safe_top, _dbg_safe_bottom)
	if not _is_mobile():
		return Vector2.ZERO
	var phys: Vector2 = _safe_insets_physical()
	var win_y: int = DisplayServer.window_get_size().y
	if win_y <= 0:
		return Vector2.ZERO
	return phys * (float(get_viewport().get_visible_rect().size.y) / float(win_y))



## 判断是否仍有有效且可见的按钮处于已登记按下状态；过期引用不会被视为按住。
func is_any_button_held() -> bool:
	for held: BaseButton in _guard_held_buttons:
		if is_instance_valid(held) and held.is_visible_in_tree():
			return true
	return false

## 记录按钮按下，并把按钮名补入本帧点击诊断；是否拦截后续抬起由窗口展示事件决定。
func _guard_held(b: BaseButton) -> void:
	_guard_held_buttons.append(b)

	if _probe_pending:
		_probe_btn = String(b.name)

## 移除已抬起按钮；无剩余按住项时解除拦截，非诊断模式也关闭 _input 处理。
func _guard_released(b: BaseButton) -> void:
	_guard_held_buttons.erase(b)

	if _guard_held_buttons.is_empty() and _guard_active:
		_guard_active = false
		if not _probe_enabled:
			set_process_input(false)

## 调试时记录按下；跨窗口保护启用时消费下一次抬起，并复位按钮按压状态，阻止误触原页面。
func _input(event: InputEvent) -> void:
	if _probe_enabled and _is_probe_press(event):
		_probe_begin(
			(
				(event as InputEventMouseButton).position
				if event is InputEventMouseButton
				else (event as InputEventScreenTouch).position
			),
			false
		)
	if not _guard_active:
		return
	var is_release: bool = (
		(event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed)
	)
	if not is_release:
		return
	get_viewport().set_input_as_handled()
	_guard_active = false
	var blocked: PackedStringArray = PackedStringArray()
	for b in _guard_held_buttons:
		if not is_instance_valid(b):
			continue
		blocked.append(String(b.name))

		# 切换 disabled 复位按钮内部按压状态，再恢复原值；不能仅吞掉抬起而让旧按钮一直保持按下。
		var was_disabled := b.disabled
		b.disabled = true
		b.disabled = was_disabled
	_guard_held_buttons.clear()
	if not _probe_enabled:
		set_process_input(false)

	(
		EventBus
		. emit_event(
			EventName.UI_TAP_BLOCKED,
			{
				"btns": ",".join(blocked),
				"count": blocked.size(),
			}
		)
	)

## 从窗口级信号捕获按下，与节点输入路径合并为同一条诊断。
func _on_window_input_probe(event: InputEvent) -> void:
	if not _is_probe_press(event):
		return
	if event is InputEventMouseButton:
		_probe_begin((event as InputEventMouseButton).position, true)
	else:
		_probe_begin((event as InputEventScreenTouch).position, true)

## 只识别触屏或鼠标按钮的按下事件，不将移动和抬起计为新的点击。
func _is_probe_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	return false

## 首个入口保存坐标并安排一次延后输出，其余入口只补充来源标记。
func _probe_begin(pos: Vector2, from_window_signal: bool) -> void:
	if not _probe_pending:
		_probe_pending = true
		_probe_unhandled = false
		_probe_btn = ""
		_probe_via_win = false
		_probe_via_input = false
		_probe_pos = pos

		call_deferred("_flush_probe")
	if from_window_signal:
		_probe_via_win = true
	else:
		_probe_via_input = true

## 返回当前悬停控件的节点路径、鼠标过滤方式与类型；无控件时返回空串。
func _probe_hovered_path() -> String:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null or not is_instance_valid(hovered):
		return ""

	var path: String = String(hovered.get_path()).trim_prefix("/root/")

	return (
		"%s|%s|%s"
		% [
			path,
			_mouse_filter_name(hovered.get_mouse_filter_with_override()),
			hovered.get_class(),
		]
	)

## 沿父链查找所属顶层窗口；找不到返回 null，不创建窗口。
func _find_owner_window(node: Node) -> UIFrameWindow:
	var n: Node = node
	while n != null:
		if n is UIFrameWindow:
			return n as UIFrameWindow
		n = n.get_parent()
	return null

## 把 Control 的输入过滤枚举转成诊断文本，未知值保留数值便于排查。
func _mouse_filter_name(f: int) -> String:
	match f:
		Control.MOUSE_FILTER_STOP:
			return "STOP"
		Control.MOUSE_FILTER_PASS:
			return "PASS"
		Control.MOUSE_FILTER_IGNORE:
			return "IGNORE"
	return "unknown(%d)" % f

## 在当前输入传播后汇总窗口/节点来源、悬停对象与消费情况，并通过产品事件总线输出。
func _flush_probe() -> void:
	if not _probe_pending:
		return
	_probe_pending = false
	var via: PackedStringArray = PackedStringArray()
	if _probe_via_win:
		via.append("win")
	if _probe_via_input:
		via.append("input")
	var payload: Dictionary = {
		"x": int(_probe_pos.x),
		"y": int(_probe_pos.y),
		"node": _probe_hovered_path(),
		"eaten": not _probe_unhandled,
		"via": ",".join(via),
	}

	if _probe_btn != "":
		payload["btn"] = _probe_btn
	EventBus.emit_event(EventName.INPUT_TAP, payload)

## 按框架实际窗口顺序从上往下查找埋点来源，优先取弹窗名，其次取页面名。
func _current_top_source() -> String:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	for i in range(ordered.size() - 1, -1, -1):
		var win: UIFrameWindow = ordered[i]
		if not is_instance_valid(win):
			continue
		var dlg: String = win.get_dlg_name()
		if dlg != "":
			return dlg
		var scr: String = win.get_scr_name()
		if scr != "":
			return scr
	return ""


## 以下开关只控制产品启动预热入口，窗口遮挡与可见性仍由框架负责。

var _async_warm_allowed: bool = true # 启动预热阶段的异步入口开关；关闭后已有调用方统一改用同步展示。

## 结束启动期异步预热使用窗口；后续 show_ui_async 入口直接走同步展示，不取消已经开始的任务。
func close_async_warm_window() -> void:
	_async_warm_allowed = false

## 预热阶段委托框架异步加载；阶段结束后仍保留同一调用入口，但立即按同步路径展示。
func show_ui_async(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if not _async_warm_allowed:
		return show_ui(ui_name, params)
	return await super.show_ui_async(ui_name, params)

## 在框架创建产品窗口后接入按钮保护；元数据标记避免与场景预处理重复连接。
func _on_product_window_created(_ui_name: String, win: UIFrameWindow) -> void:
	_attach_product_button_guard(win)

## 递归为按钮绑定按下/抬起登记，每个节点只接一次；运行时新增子树需再次经过此入口。
func _attach_product_button_guard(node: Node) -> void:
	if node is BaseButton and not node.has_meta("_product_press_guard"):
		var button := node as BaseButton
		button.set_meta("_product_press_guard", true)
		button.button_down.connect(_guard_held.bind(button))
		button.button_up.connect(_guard_released.bind(button))
	for child in node.get_children():
		_attach_product_button_guard(child)

## 发布产品 UI_SHOW 事件；若旧按钮尚未抬起，启用一次跨层输入保护。
func _on_product_window_shown(ui_name: String, win: UIFrameWindow) -> void:
	if not is_instance_valid(win):
		return
	EventBus.emit_event(EventName.UI_SHOW, {"ui": ui_name, "layer": win.ui_layer, "fullscreen": win.is_fullscreen, "depth": get_window_count(win.ui_layer)})
	if not _guard_held_buttons.is_empty():
		_guard_active = true
		set_process_input(true)

## 关闭页面时更新埋点来源，并发布 UI_HIDE；窗口栈本身已由框架管理。
func _on_product_window_hidden(ui_name: String, win: UIFrameWindow) -> void:
	if not is_instance_valid(win):
		return
	var dialog: String = win.get_dlg_name()
	if dialog.is_empty() and not win.get_scr_name().is_empty():
		Tracker.notify_scr_closed(_current_top_source())
	EventBus.emit_event(EventName.UI_HIDE, {"ui": ui_name, "layer": win.ui_layer, "depth": get_window_count(win.ui_layer)})

## 按绘制顺序输出窗口状态、层级与遮罩申请数，供诊断使用，不改变窗口栈。
func debug_dump_stack() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for win: UIFrameWindow in _ordered_windows():
		lines.append("%s state=%d layer=%d z=%d" % [win._ui_name, win.get_window_state(), win.ui_layer, win.z_index])
	lines.append("mask requests=%d" % _modal_mask.request_count())
	return "\n".join(lines)

## 把后创建的控件树交给所属窗口初始化，再接入产品按钮保护，补齐静态场景已有的装配过程。
func initialize_dynamic_widget(window: UIBaseWindow, root: Control) -> void:
	window.initialize_dynamic_widget(root)
	_attach_product_button_guard(root)


## 同一个注入端口覆盖静态场景、托管子窗口和后续动态控件。
func _prepare_product_scene(node: Node) -> void:
	ContentSceneBindings.apply(node)
	_attach_product_button_guard(node)


## 为调试探针记录输入确实未被上层消费，然后交回框架处理系统返回等事件。
func _unhandled_input(event: InputEvent) -> void:
	if _probe_pending and _is_probe_press(event):
		_probe_unhandled = true
	super._unhandled_input(event)
