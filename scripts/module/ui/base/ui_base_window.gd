class_name UIBaseWindow
extends Control



enum WindowState{INVALID, CREATING, SHOWING, HIDDEN, CLOSING, DESTROYED}

var _window_state: int = WindowState.INVALID

func get_window_state() -> int:
    return _window_state

func is_showing() -> bool:
    return _window_state == WindowState.SHOWING

func is_hidden() -> bool:
    return _window_state == WindowState.HIDDEN



func _do_create() -> void :
    _window_state = WindowState.CREATING
    _attach_button_sounds(self)
    _window_state = WindowState.HIDDEN
    on_create()

func _do_show(params: Dictionary = {}) -> void :
    _window_state = WindowState.SHOWING
    visible = true
    _resume_all_timers()
    if not _update_listeners.is_empty() or not _per_second_listeners.is_empty():
        set_process(true)
    on_show(params)

func _do_hide() -> void :




    @warning_ignore("redundant_await")
    await on_hide()

    if _window_state == WindowState.SHOWING:
        return
    _window_state = WindowState.HIDDEN
    _disconnect_all_managed()
    _pause_all_timers()
    set_process(false)
    visible = false

func _do_destroy() -> void :
    destroy_all_children()
    _window_state = WindowState.DESTROYED
    on_destroy()
    _disconnect_all_managed()
    _destroy_all_timers()
    _clear_all_listeners()



func on_create() -> void :
    pass

func on_show(params: Dictionary = {}) -> void :
    pass

func on_hide() -> void :
    pass

func on_destroy() -> void :
    pass



var _managed_connections: Array[Dictionary] = []

func connect_managed(sig: Signal, callable: Callable, flags: int = 0) -> void :
    sig.connect(callable, flags)
    _managed_connections.append({"signal": sig, "callable": callable})

func connect_managed_once(sig: Signal, callable: Callable) -> void :
    sig.connect(callable, CONNECT_ONE_SHOT)
    _managed_connections.append({"signal": sig, "callable": callable, "one_shot": true})

func disconnect_managed(sig: Signal, callable: Callable) -> void :
    if sig.is_connected(callable):
        sig.disconnect(callable)
    _managed_connections = _managed_connections.filter(
        func(c: Dictionary) -> bool: return not (c.signal == sig and c.callable == callable)
    )

func _disconnect_all_managed() -> void :
    for conn in _managed_connections:
        if conn.signal .is_connected(conn.callable):
            conn.signal .disconnect(conn.callable)
    _managed_connections.clear()



var _managed_timers: Array[Timer] = []

func create_countdown(sec: float, callable: Callable) -> Timer:
    var t: = Timer.new()
    t.wait_time = sec
    t.one_shot = true
    t.timeout.connect(callable)
    t.timeout.connect(_on_managed_timer_done.bind(t))
    add_child(t)
    t.start()
    _managed_timers.append(t)
    return t

func create_tick(interval: float, callable: Callable) -> Timer:
    var t: = Timer.new()
    t.wait_time = interval
    t.one_shot = false
    t.timeout.connect(callable)
    add_child(t)
    t.start()
    _managed_timers.append(t)
    return t

func remove_timer(timer: Timer) -> void :
    if is_instance_valid(timer):
        timer.stop()
        timer.queue_free()
    _managed_timers.erase(timer)

func _pause_all_timers() -> void :
    for t in _managed_timers:
        if is_instance_valid(t):
            t.paused = true

func _resume_all_timers() -> void :
    for t in _managed_timers:
        if is_instance_valid(t):
            t.paused = false

func _destroy_all_timers() -> void :
    for t in _managed_timers:
        if is_instance_valid(t):
            t.stop()
            t.queue_free()
    _managed_timers.clear()

func _on_managed_timer_done(timer: Timer) -> void :
    _managed_timers.erase(timer)
    if is_instance_valid(timer):
        timer.queue_free()



var _update_listeners: Array[Callable] = []
var _per_second_listeners: Array[Callable] = []
var _per_second_accumulator: float = 0.0

func add_update_listener(callable: Callable) -> void :
    _update_listeners.append(callable)
    set_process(true)

func add_per_second_listener(callable: Callable) -> void :
    _per_second_listeners.append(callable)
    set_process(true)

func remove_update_listener(callable: Callable) -> void :
    _update_listeners.erase(callable)
    _check_process_needed()

func remove_per_second_listener(callable: Callable) -> void :
    _per_second_listeners.erase(callable)
    _check_process_needed()

func _process(delta: float) -> void :
    for cb in _update_listeners:
        cb.call()
    if not _per_second_listeners.is_empty():
        _per_second_accumulator += delta
        if _per_second_accumulator >= 1.0:
            _per_second_accumulator -= 1.0
            for cb in _per_second_listeners:
                cb.call()

func _check_process_needed() -> void :
    if _update_listeners.is_empty() and _per_second_listeners.is_empty():
        set_process(false)

func _clear_all_listeners() -> void :
    _update_listeners.clear()
    _per_second_listeners.clear()
    _per_second_accumulator = 0.0
    set_process(false)



var _managed_children: Array[UIChildWindow] = []

func create_child(scene: PackedScene, params: Dictionary = {}) -> UIChildWindow:
    var node: = scene.instantiate()
    var child: = node as UIChildWindow
    if child == null:
        push_error("UIBaseWindow: create_child scene root must extend UIChildWindow")
        if node != null:
            node.queue_free()
        return null
    add_child(child)
    child._do_create()
    child._do_show(params)
    _managed_children.append(child)
    return child

func destroy_child(child: UIChildWindow) -> void :
    if not is_instance_valid(child):
        return


    if child._window_state == WindowState.SHOWING:
        await child._do_hide()

        if not is_instance_valid(child):
            return
    child._do_destroy()
    _managed_children.erase(child)
    child.queue_free()

func destroy_all_children() -> void :


    for child in _managed_children.duplicate():
        destroy_child(child)

func get_child_window(child_name: String) -> UIChildWindow:
    for child in _managed_children:
        if is_instance_valid(child) and child.name == child_name:
            return child
    return null



const _BTN_SOUND_BOUND_META: StringName = &"_btn_click_sound_bound"

func _attach_button_sounds(node: Node) -> void :
    if node is BaseButton:
        var b: = node as BaseButton
        if not b.has_meta(_BTN_SOUND_BOUND_META):
            b.set_meta(_BTN_SOUND_BOUND_META, true)
            b.button_down.connect( func() -> void : SoundManager.play(SoundManager.Kind.BTN_CLICK))
    for child in node.get_children():
        _attach_button_sounds(child)

func claim_button_sound(button: BaseButton) -> void :
    if is_instance_valid(button):
        button.set_meta(_BTN_SOUND_BOUND_META, true)



func play_press_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void :
    UIHelper.play_press_scale(node, base_scale)

func play_release_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void :
    UIHelper.play_release_scale(node, base_scale)

func bind_press_release_scale(button: BaseButton, base_scale: Vector2 = Vector2.ONE) -> void :
    UIHelper.bind_press_release_scale(button, base_scale)



func find_node_by_name(node_name: String) -> Node:
    return find_child(node_name, true, false)

func _ready() -> void :
    set_process(false)

func _notification(what: int) -> void :
    if what == NOTIFICATION_PREDELETE:
        destroy_all_children()
