class_name ScrollDragHelper
extends Node












const _DRAG_THRESHOLD: float = 12.0
const _MOTION_WINDOW_SEC: float = 0.06


@export var with_inertia: bool = false
@export var friction: float = 0.95
@export var min_velocity: float = 30.0
@export var elastic_max_overscroll: float = 120.0
@export var elastic_resist: float = 0.5
@export var elastic_bounce_back_sec: float = 0.28


enum State{IDLE, PRESSING, DRAGGING, DRIFTING, ELASTIC}
var _state: int = State.IDLE
var _velocity: Vector2 = Vector2.ZERO
var _overscroll: float = 0.0
var _bounce_tween: Tween = null
var _consumed_drift_release: bool = false
var _recent_motions: Array = []


var _scroll: ScrollContainer
var _is_pressing: bool = false
var _drag_active: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _active_pointer_index: int = -1

static func attach(scroll: ScrollContainer, with_inertia: bool = false) -> ScrollDragHelper:
    if scroll == null:
        push_error("ScrollDragHelper.attach: scroll is null")
        return null

    for child in scroll.get_children():
        if child is ScrollDragHelper:
            var existing: = child as ScrollDragHelper
            existing.with_inertia = with_inertia
            return existing
    var helper: = ScrollDragHelper.new()
    helper.name = "_ScrollDragHelper"
    helper._scroll = scroll
    helper.with_inertia = with_inertia
    scroll.add_child(helper)
    return helper

func _ready() -> void :

    if _scroll != null and not _scroll.visibility_changed.is_connected(_on_scroll_visibility_changed):
        _scroll.visibility_changed.connect(_on_scroll_visibility_changed)
    set_process(false)

func _notification(what: int) -> void :
    if what == NOTIFICATION_PREDELETE:
        _reset_all()



func _start_drift() -> void :
    if _scroll == null or _max_scroll() <= 0:
        _stop_drift()
        return
    _state = State.DRIFTING
    set_process(true)

func _stop_drift() -> void :
    _state = State.IDLE
    _velocity = Vector2.ZERO
    set_process(false)

func _process(delta: float) -> void :
    match _state:
        State.DRIFTING:
            _tick_drift(delta)
        State.ELASTIC:
            _tick_elastic(delta)

func _tick_drift(delta: float) -> void :
    var new_y: float = float(_scroll.scroll_vertical) + _velocity.y * delta
    var max_y: float = float(_max_scroll())

    if new_y < 0.0:
        _enter_elastic(new_y)
        return
    if new_y > max_y:
        _enter_elastic(new_y - max_y)
        return

    _scroll.scroll_vertical = int(new_y)
    _velocity.y *= pow(friction, delta * 60.0)
    if absf(_velocity.y) < min_velocity:
        _stop_drift()

func _enter_elastic(out_of_bounds: float) -> void :
    _state = State.ELASTIC
    _overscroll = clampf(out_of_bounds, - elastic_max_overscroll, elastic_max_overscroll)

    if _overscroll < 0.0:
        _scroll.scroll_vertical = 0
    else:
        _scroll.scroll_vertical = _max_scroll()
    _apply_overscroll_visual()
    set_process(true)

func _tick_elastic(delta: float) -> void :

    if absf(_velocity.y) > 0.1:
        _overscroll += _velocity.y * delta
        _overscroll = clampf(_overscroll, - elastic_max_overscroll, elastic_max_overscroll)
        _velocity.y *= pow(friction * elastic_resist, delta * 60.0)
        _apply_overscroll_visual()
        if absf(_velocity.y) < min_velocity:
            _velocity = Vector2.ZERO
            _start_bounce_back()

    elif _bounce_tween == null:
        _start_bounce_back()

func _start_bounce_back() -> void :
    if _bounce_tween != null:
        _bounce_tween.kill()
    _bounce_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _bounce_tween.tween_method(_set_overscroll, _overscroll, 0.0, elastic_bounce_back_sec)
    _bounce_tween.finished.connect( func() -> void :
        _bounce_tween = null
        _state = State.IDLE
        set_process(false))

func _set_overscroll(v: float) -> void :
    _overscroll = v
    _apply_overscroll_visual()

func _apply_overscroll_visual() -> void :
    if _scroll == null or _scroll.get_child_count() == 0:
        return
    var content: = _scroll.get_child(0) as Control
    if content == null:
        return



    content.position.y = - float(_scroll.scroll_vertical) - _overscroll

func _on_scroll_visibility_changed() -> void :
    if _scroll != null and not _scroll.is_visible_in_tree():
        _reset_all()

func _reset_all() -> void :
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

func _max_scroll() -> int:
    if _scroll == null:
        return 0
    var v_scroll: VScrollBar = _scroll.get_v_scroll_bar()
    if v_scroll == null:
        return 0
    return int(maxf(0.0, v_scroll.get_max() - v_scroll.get_page()))



func _input(event: InputEvent) -> void :
    if _scroll == null or not _scroll.is_visible_in_tree():
        _reset()
        return

    if event is InputEventScreenTouch:
        _handle_press(event.position, event.pressed, event.index)
    elif event is InputEventScreenDrag:
        if _active_pointer_index == event.index:
            _handle_motion(event.position)
    elif event is InputEventMouseButton:
        var mb: = event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT:
            _handle_press(mb.position, mb.pressed, -2)
    elif event is InputEventMouseMotion:
        if _active_pointer_index == -2 and _is_pressing:
            _handle_motion(event.position)

func _handle_press(pos: Vector2, pressed: bool, pointer_index: int) -> void :
    if pressed:
        var rect: Rect2 = _scroll.get_global_rect()
        if not rect.has_point(pos):
            return


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


        var release_v: float = _calc_release_velocity()
        var should_drift: bool = with_inertia and was_dragging and absf(release_v) > min_velocity * 2.0
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

func _handle_motion(pos: Vector2) -> void :
    if not _is_pressing:
        return
    var delta: Vector2 = pos - _last_pos
    if not _drag_active:
        if (pos - _press_pos).length() > _DRAG_THRESHOLD:
            _drag_active = true
            _state = State.DRAGGING
            _cancel_pressed_buttons(_scroll)
    if _drag_active:
        var v_enabled: bool = _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
        var h_enabled: bool = _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
        if v_enabled:
            _scroll.scroll_vertical = int(_scroll.scroll_vertical - delta.y)
        if h_enabled:
            _scroll.scroll_horizontal = int(_scroll.scroll_horizontal - delta.x)

        var dt: float = get_process_delta_time()
        if dt > 0.0:
            _recent_motions.append({"delta_y": delta.y, "dt": dt})
            _trim_recent_motions()
        get_viewport().set_input_as_handled()
    _last_pos = pos

func _reset() -> void :
    _is_pressing = false
    _drag_active = false
    _active_pointer_index = -1
    _state = State.IDLE
    _recent_motions.clear()

func _trim_recent_motions() -> void :
    var total_dt: float = 0.0
    for m in _recent_motions:
        total_dt += m.dt

    while total_dt > _MOTION_WINDOW_SEC and _recent_motions.size() > 1:
        var oldest = _recent_motions.pop_front()
        total_dt -= oldest.dt

func _calc_release_velocity() -> float:
    var total_dy: float = 0.0
    var total_dt: float = 0.0
    for m in _recent_motions:
        total_dy += m.delta_y
        total_dt += m.dt
    if total_dt < 0.001:
        return 0.0

    return - total_dy / total_dt

func _cancel_pressed_buttons(node: Node) -> void :
    if node is BaseButton:
        var btn: = node as BaseButton
        if btn.button_pressed and not btn.toggle_mode:
            btn.button_pressed = false
    for child in node.get_children():
        _cancel_pressed_buttons(child)
