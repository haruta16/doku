extends Node












const IDLE_TIMEOUT_SEC: float = 270.0
const _DEFAULT_SYSTEM_TIMEOUT_MS: int = 30000

var _tracking_idle: bool = false
var _idle_timer: Timer = null
var _idle_controls_screen: bool = false
var _last_group: int = -1
var _no_action_dyed: bool = false


func setup() -> void :
    _apply_group(ABTestManager.auto_screen_off.peek_value())


func _input(event: InputEvent) -> void :
    var current_group: int = ABTestManager.auto_screen_off.peek_value()
    if current_group != _last_group:
        _apply_group(current_group)
        return

    if not _tracking_idle:
        return
    var is_press: bool = (event is InputEventScreenTouch and event.pressed)\
or (event is InputEventMouseButton and event.pressed)
    if not is_press:
        return
    if _idle_controls_screen:
        DisplayServer.screen_set_keep_on(true)
    _idle_timer.stop()
    _idle_timer.start()


func _notification(what: int) -> void :
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

func _apply_group(group: int) -> void :
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

func _stop_idle_tracking() -> void :
    _tracking_idle = false
    _idle_controls_screen = false
    if _idle_timer != null:
        _idle_timer.stop()
        _idle_timer.queue_free()
        _idle_timer = null



func _start_idle_tracking(timer_sec: float, controls_screen: bool) -> void :
    _tracking_idle = true
    _idle_controls_screen = controls_screen
    _idle_timer = Timer.new()
    _idle_timer.wait_time = timer_sec
    _idle_timer.one_shot = true
    _idle_timer.timeout.connect(_on_idle_timeout)
    add_child(_idle_timer)
    _idle_timer.start()

func _on_idle_timeout() -> void :
    if _idle_controls_screen:
        DisplayServer.screen_set_keep_on(false)
    if not _no_action_dyed:
        _no_action_dyed = true
        ABTestManager.dye_at_no_action_270()



func _get_android_screen_timeout_ms() -> int:
    if not OS.has_feature("android"):
        return _DEFAULT_SYSTEM_TIMEOUT_MS

    var ActivityThread: = JavaClassWrapper.wrap("android.app.ActivityThread")
    if JavaClassWrapper.get_exception() != null or ActivityThread == null:

        return _DEFAULT_SYSTEM_TIMEOUT_MS

    var app = ActivityThread.currentApplication()
    if JavaClassWrapper.get_exception() != null or app == null:

        return _DEFAULT_SYSTEM_TIMEOUT_MS

    var resolver = app.getContentResolver()
    if JavaClassWrapper.get_exception() != null or resolver == null:

        return _DEFAULT_SYSTEM_TIMEOUT_MS

    var SettingsSystem: = JavaClassWrapper.wrap("android.provider.Settings$System")
    if JavaClassWrapper.get_exception() != null or SettingsSystem == null:

        return _DEFAULT_SYSTEM_TIMEOUT_MS

    var timeout_ms: int = SettingsSystem.getInt(resolver, "screen_off_timeout", _DEFAULT_SYSTEM_TIMEOUT_MS)
    if JavaClassWrapper.get_exception() != null:

        return _DEFAULT_SYSTEM_TIMEOUT_MS

    return timeout_ms
