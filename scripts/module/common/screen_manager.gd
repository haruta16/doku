# 屏幕常亮 / 自动熄屏管理（autoload 名 ScreenManager）
# 目标：游戏中别熄屏，但挂机 270 秒后要放行系统的熄屏，同时给 A/B 打一个「无操作」标记
extends Node

const IDLE_TIMEOUT_SEC: float = 270.0 # 无操作判定阈值（秒），与埋点命名 270 对应
const _DEFAULT_SYSTEM_TIMEOUT_MS: int = 30000 # 读不到系统设置时的兜底熄屏时间（30 秒）

var _tracking_idle: bool = false # 是否正在计时无操作
var _idle_timer: Timer = null # 无操作计时器，每次 _apply_group 重建
var _idle_controls_screen: bool = false # 本组策略下，是否由我们来关掉常亮
var _last_group: int = -1 # 上次生效的 A/B 分组，用来发现分组变化
var _no_action_dyed: bool = false # 本次运行是否已上报过「无操作」埋点，只报一次


# 启动时按当前 A/B 分组应用一次策略（由 launcher 调用）
func setup() -> void:
	_apply_group(ABTestManager.auto_screen_off.peek_value())


# 每次输入都检查：A/B 分组变了就立刻换策略；有按下就续上常亮并重置无操作计时
func _input(event: InputEvent) -> void:
	var current_group: int = ABTestManager.auto_screen_off.peek_value()
	if current_group != _last_group:
		_apply_group(current_group)
		return

	if not _tracking_idle:
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not is_press:
		return
	if _idle_controls_screen:
		DisplayServer.screen_set_keep_on(true)
	_idle_timer.stop()
	_idle_timer.start()


# 切后台就别计时了，回前台恢复常亮并重新计时
func _notification(what: int) -> void:
	if not _tracking_idle:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _idle_timer != null:
				_idle_timer.stop()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if _idle_controls_screen:
				DisplayServer.screen_set_keep_on(true)
			if _idle_timer != null:
				_idle_timer.start()


# 按分组套用策略：0 组（或非 Android）一直常亮；1 组让系统先熄
# 1 组下还要读系统熄屏时间：系统自己就很晚（>270s）就不插手，否则提前 system_timeout 关掉常亮
func _apply_group(group: int) -> void:
	_last_group = group
	_stop_idle_tracking()

	var keep_on: bool = true
	var timer_sec: float = IDLE_TIMEOUT_SEC
	var controls_screen: bool = false

	if group != 0 and OS.has_feature("android"):
		var system_timeout_ms: int = _get_android_screen_timeout_ms()
		if system_timeout_ms > 270000:
			keep_on = false
		else:
			var system_timeout_sec: float = system_timeout_ms / 1000.0
			timer_sec = maxf(1.0, IDLE_TIMEOUT_SEC - system_timeout_sec)
			controls_screen = true

	DisplayServer.screen_set_keep_on(keep_on)
	_start_idle_tracking(timer_sec, controls_screen)


# 停表并销毁计时器（计时器是每次重建的临时节点）
func _stop_idle_tracking() -> void:
	_tracking_idle = false
	_idle_controls_screen = false
	if _idle_timer != null:
		_idle_timer.stop()
		_idle_timer.queue_free()
		_idle_timer = null


# 新建一次性计时器开始计无操作时长
func _start_idle_tracking(timer_sec: float, controls_screen: bool) -> void:
	_tracking_idle = true
	_idle_controls_screen = controls_screen
	_idle_timer = Timer.new()
	_idle_timer.wait_time = timer_sec
	_idle_timer.one_shot = true
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)
	_idle_timer.start()


# 挂机到点：放行熄屏；本次运行第一次到点时补一条 A/B 埋点
func _on_idle_timeout() -> void:
	if _idle_controls_screen:
		DisplayServer.screen_set_keep_on(false)
	if not _no_action_dyed:
		_no_action_dyed = true
		ABTestManager.dye_at_no_action_270()


# 反射读 Android 系统设置里的 screen_off_timeout（毫秒），任何一步失败都退回默认值
func _get_android_screen_timeout_ms() -> int:
	if not OS.has_feature("android"):
		return _DEFAULT_SYSTEM_TIMEOUT_MS

	var ActivityThread := JavaClassWrapper.wrap("android.app.ActivityThread")
	if JavaClassWrapper.get_exception() != null or ActivityThread == null:
		return _DEFAULT_SYSTEM_TIMEOUT_MS

	var app = ActivityThread.currentApplication()
	if JavaClassWrapper.get_exception() != null or app == null:
		return _DEFAULT_SYSTEM_TIMEOUT_MS

	var resolver = app.getContentResolver()
	if JavaClassWrapper.get_exception() != null or resolver == null:
		return _DEFAULT_SYSTEM_TIMEOUT_MS

	var SettingsSystem := JavaClassWrapper.wrap("android.provider.Settings$System")
	if JavaClassWrapper.get_exception() != null or SettingsSystem == null:
		return _DEFAULT_SYSTEM_TIMEOUT_MS

	var timeout_ms: int = SettingsSystem.getInt(
		resolver, "screen_off_timeout", _DEFAULT_SYSTEM_TIMEOUT_MS
	)
	if JavaClassWrapper.get_exception() != null:
		return _DEFAULT_SYSTEM_TIMEOUT_MS

	return timeout_ms
