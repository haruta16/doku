## 局内省电管理器：空闲时降低帧率、裁去透明装饰并启用静态图层缓存，输入时立即唤醒。
extends Node

const IDLE_DELAY_SEC: float = 1.5
const ACTIVE_FPS: int = 60
const IDLE_FPS: int = 30

var idle_fps: int = IDLE_FPS

const _IDLE_FPS_PAGES: Array[StringName] = [UiName.GAME, UiName.DAILY_GAME]

const _CULL_PATHS: Array[NodePath] = [
	^"Root/Overlay",
	^"Root/VBoxContainer/BoardContainer/BoardOuterGlow",
	^"Root/VBoxContainer/RuleBar/Control/Glow",
]

var enabled: bool = true

var freeze_fps_override: bool = false

var cache_enabled: bool = true
var _cache: StaticLayerCache = StaticLayerCache.new()

var _last_touch_ms: int = 0

var _cull_targets: Array[CanvasItem] = []

var _culled: Dictionary = {}

var _armed: bool = false


func _ready() -> void:
	set_process_input(false)

	if ABTestManager.is_app_start_dyed():
		_decide_group()
	else:
		ABTestManager.init_done.connect(_decide_group, CONNECT_ONE_SHOT)


func _decide_group() -> void:
	if ABTestManager.system_dfps.is_power_saving_enabled():
		_arm()
	else:
		print("[PowerSaver] system_dfps=对照组:局内省电优化不启用")


## 只注册一次绘制前回调和输入监听，同时启用格子静止优化。
func _arm() -> void:
	if _armed:
		return
	_armed = true
	CellView.cat_settle_enabled = true

	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
	UIManager.events.window_shown.connect(_on_window_shown)

	UIManager.events.window_hidden.connect(_on_window_shown)
	_last_touch_ms = Time.get_ticks_msec()
	set_process_input(true)
	print("[PowerSaver] system_dfps=实验组:局内省电优化已启用")


func is_armed() -> bool:
	return _armed


## 触摸或拖动时恢复 60 帧并撤销静态缓存，使交互立即回到动态渲染。
func _input(event: InputEvent) -> void:
	if not _armed:
		return

	if (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or event is InputEventScreenDrag
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		or (event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0)
	):
		_last_touch_ms = Time.get_ticks_msec()
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			_cache.trace("touch_press %s" % event.get_class())
		if Engine.max_fps != ACTIVE_FPS and not freeze_fps_override:
			Engine.max_fps = ACTIVE_FPS

		_cache.disable()


const SHOW_FULL_FPS_SEC: float = 3.0


func _on_window_shown(_ui_name: String, _win: Object) -> void:
	wake(SHOW_FULL_FPS_SEC)


func _register_cull_targets(page: Node) -> void:
	for p: NodePath in _CULL_PATHS:
		var ci: CanvasItem = page.get_node_or_null(p) as CanvasItem
		if ci != null and not _cull_targets.has(ci):
			_cull_targets.append(ci)


## 每帧检查顶部页面、透明节点和静止状态，再决定缓存与目标帧率。
func _on_frame_pre_draw() -> void:
	var top: UIFrameWindow = UIManager.get_top_window()
	var on_game_page: bool = top != null and StringName(top.get_ui_name()) in _IDLE_FPS_PAGES
	if on_game_page and _cull_targets.size() < _CULL_PATHS.size() * _IDLE_FPS_PAGES.size():
		_register_cull_targets(top)
	_update_culling()

	var no_touch: bool = (
		enabled
		and on_game_page
		and not freeze_fps_override
		and Time.get_ticks_msec() - _last_touch_ms > int(IDLE_DELAY_SEC * 1000.0)
	)
	var t0: int = Time.get_ticks_usec()
	_cache.update(top as Control if on_game_page else _cache.page(), no_touch and cache_enabled)
	_cache_cost_us = lerpf(_cache_cost_us, float(Time.get_ticks_usec() - t0), 0.1)
	_tick_test_tap()

	_update_fps(no_touch and _cache.is_page_quiet(top as Control if on_game_page else null))


func _update_fps(idle: bool) -> void:
	if freeze_fps_override:
		return
	var want: int = idle_fps if idle else ACTIVE_FPS
	if Engine.max_fps != want:
		_cache.trace("max_fps %d->%d" % [Engine.max_fps, want])
		Engine.max_fps = want


## 隐藏几乎全透明且不拦截输入的节点，重新可见时仅还原本管理器隐藏的项。
func _update_culling() -> void:
	for i in range(_cull_targets.size() - 1, -1, -1):
		var ci: CanvasItem = _cull_targets[i]
		if not is_instance_valid(ci):
			_cull_targets.remove_at(i)
			continue
		var id: int = ci.get_instance_id()
		var transparent: bool = enabled and _draws_nothing(ci)
		if transparent:
			if ci.visible:
				ci.visible = false
				_culled[id] = true
		elif _culled.has(id):
			_culled.erase(id)
			ci.visible = true


static func _draws_nothing(ci: CanvasItem) -> bool:
	var a: float = ci.modulate.a * ci.self_modulate.a
	if ci is ColorRect:
		a *= (ci as ColorRect).color.a
	if ci is Control and (ci as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
		return false
	return a < 0.007


## 将活跃截止时间向后延长，恢复正常帧率并关闭缓存。
func wake(hold_sec: float = IDLE_DELAY_SEC) -> void:
	if not _armed:
		return
	_last_touch_ms = maxi(
		_last_touch_ms, Time.get_ticks_msec() + int((hold_sec - IDLE_DELAY_SEC) * 1000.0)
	)
	if Engine.max_fps != ACTIVE_FPS and not freeze_fps_override:
		Engine.max_fps = ACTIVE_FPS
	_cache.disable()


func set_enabled(on: bool) -> void:
	if on:
		_arm()
	elif not _armed:
		return
	enabled = on
	_last_touch_ms = Time.get_ticks_msec()
	_on_frame_pre_draw()


func cache_debug() -> String:
	return (
		(
			"system_dfps=%s armed=%s settle=%s "
			% [
				str(ABTestManager.system_dfps.value()),
				str(_armed),
				str(CellView.cat_settle_enabled)
			]
		)
		+ (
			"cache active=%s refresh=%d toggles=%d last_off='%s' cost=%.0fus(tw=%.0f quiet=%.0f) blocker='%s'"
			% [
				_cache.is_active(),
				_cache.refresh_count,
				_cache.toggle_count,
				_cache.last_off_reason,
				_cache_cost_us,
				_cache.cost_tween_us,
				_cache.cost_quiet_us,
				_cache.quiet_blocker()
			]
		)
		+ (
			" playing=%d active_particles=%d"
			% [_cache._playing.size(), _cache._active_particles.size()]
		)
	)


var _cache_cost_us: float = 0.0

var _test_tap_k: int = -1
var _test_tap_pos: Vector2 = Vector2.ZERO
var _test_tap_count: int = -1


func arm_test_tap(k: int, pos: Vector2) -> void:
	_test_tap_k = k
	_test_tap_pos = pos
	_test_tap_count = -1


func _tick_test_tap() -> void:
	if _test_tap_k < 0:
		return
	if _test_tap_count < 0:
		if _cache.is_active():
			_test_tap_count = 0
		else:
			return
	if _test_tap_count == _test_tap_k:
		_cache.trace("test_tap inject k=%d" % _test_tap_k)
		for pressed: bool in [true, false]:
			var ev := InputEventScreenTouch.new()
			ev.index = 0
			ev.pressed = pressed
			ev.position = _test_tap_pos
			Input.parse_input_event(ev)
		_test_tap_k = -1
		return
	_test_tap_count += 1
