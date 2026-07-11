@tool
class_name CellView
extends Control

@export var region_colors: PackedColorArray = PackedColorArray()

@onready var _bg: Panel = $BgPanel
@onready var _glow: Sprite2D = $Glows/Glow
@onready var _glow2: Sprite2D = $Glows/Glow2
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _scale_anim: AnimationPlayer = $ScalePlayer
@onready var _cross: Node = $Crosses/CrossOut
@onready var _hint_light: Sprite2D = $Frames/HighLight
@onready var _cat_icon: CanvasItem = $CatIcon
@onready var _cat_prompt: Sprite2D = $CatPrompt
@onready var _prompt_frame: Sprite2D = $Frames/PromptFrame
@onready var _prompt_cross_out: Control = $Crosses/PromptCrossOut

const _HINT_ALPHA_MIN: float = 50.0 / 255.0
const _HINT_HALF_CYCLE: float = 0.65
const _HINT_FADE_OUT: float = 0.12

var _hint_tween: Tween = null
var _frame_tween: Tween = null
var _preview_tween: Tween = null

@export var _region_color: Color = Color.WHITE
var _state: int = CellState.EMPTY
var _style: StyleBoxFlat

const DESIGN_CELL_VISUAL_PX: float = 97.55
const DESIGN_CORNER_VISUAL_PX: float = 10.0

const _DOUBLE_TAP_MARK_GRACE_MS: int = 1000
var _ever_marked_x: bool = false
var _ever_errored: bool = false
var _mark_entered_time_ms: int = -1
var _ever_marked_x_snapshot: bool = false
var _press_shrunk: bool = false

const _IDLE_INTERVAL: float = 5.0
const CROSS_OUT_APPEAR_DURATION: float = 0.49
var _idle_timer: Timer = null
var _cat_cry_loop: bool = false
var _demo_cat_no_idle: bool = false


func _ready() -> void:
    _style = StyleBoxFlat.new()

    set_corner_radius_compensated(1.0)
    _update_bg()

    if Engine.is_editor_hint():
        return

    _idle_timer = Timer.new()
    _idle_timer.wait_time = _IDLE_INTERVAL
    _idle_timer.one_shot = false
    _idle_timer.autostart = false
    add_child(_idle_timer)
    _idle_timer.timeout.connect(_on_idle_timer_timeout)
    _anim.animation_finished.connect(_on_anim_finished)

    _set_children_mouse_ignore(self)

    _reset_to_empty_baseline()


func _reset_to_empty_baseline() -> void:
    if _hint_tween != null and _hint_tween.is_valid():
        _hint_tween.kill()
    _hint_tween = null
    if _frame_tween != null and _frame_tween.is_valid():
        _frame_tween.kill()
    _frame_tween = null
    if _preview_tween != null and _preview_tween.is_valid():
        _preview_tween.kill()
    _preview_tween = null
    if _idle_timer != null:
        _idle_timer.stop()

    _anim.stop()
    _anim.play("RESET")
    _anim.advance(0.0)

    var cat_spine := _cat_icon as SpineSprite
    if cat_spine != null:
        var st := cat_spine.get_animation_state()
        if st != null:
            st.set_animation("idle", false, 0)
        cat_spine.update_skeleton(0.0)

    _glow.visible = false
    _glow2.visible = false

    _cross.visible = false
    _hint_light.visible = false
    _prompt_frame.visible = false
    _prompt_frame.modulate.a = 1.0
    _cat_prompt.modulate = Color.WHITE
    _cat_prompt.scale = Vector2.ONE
    _bg.modulate.a = 1.0
    _apply_draft_visual(CellState.EMPTY)

    _state = CellState.EMPTY
    _cat_cry_loop = false
    _demo_cat_no_idle = false
    reset_clap_tracking()
    set_auto_mark_locked(false)

    _apply_eliminate_effect()


func _apply_eliminate_effect() -> void:
    if _is_eliminate_shrink_cross():
        $Crosses.scale = Vector2(0.865, 0.865)
        $Glows.scale = Vector2(0.865, 0.865)
    if _is_eliminate_remove_glow():
        $Glows.visible = false


func _set_children_mouse_ignore(node: Node) -> void:
    for child in node.get_children():
        if child is Control:
            (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _set_children_mouse_ignore(child)


func set_corner_radius(rad: int) -> void:
    if _style == null:
        return
    _style.corner_radius_top_left = rad
    _style.corner_radius_top_right = rad
    _style.corner_radius_bottom_right = rad
    _style.corner_radius_bottom_left = rad
    _bg.add_theme_stylebox_override("panel", _style)


func set_corner_radius_compensated(container_scale: float) -> void:
    if _style == null:
        return
    if container_scale <= 0.0:
        return
    var rad: int = maxi(1, int(round(DESIGN_CORNER_VISUAL_PX / container_scale)))
    set_corner_radius(rad)


func set_region_color(color: Color) -> void:
    _region_color = color
    if _style != null:
        _update_bg()


func get_region_color() -> Color:
    return _region_color


func change_state(params: Dictionary) -> void:
    var state: int = params.get("state", _state)
    var is_play_anim: bool = params.get("play_anim", true)
    var show_cat_visual: bool = params.get("show_cat_visual", true)

    var appear_anim: String = params.get("appear_anim", "")

    var disappear_anim: String = params.get("disappear_anim", "")

    var lock_anim: String = params.get("lock_anim", "")

    var split_press: bool = params.get("split_press", false)
    if _state == state:
        return

    if _state == CellState.LOCKED_MARK:
        return
    var prev_state := _state

    if _is_draft_state(state) or (_is_draft_state(prev_state) and state == CellState.EMPTY):
        _state = state
        _apply_draft_visual(state)
        return

    if _is_draft_state(prev_state):
        _apply_draft_visual(CellState.EMPTY)
    _state = state

    if state == CellState.MARK:
        _mark_entered_time_ms = Time.get_ticks_msec()
        _ever_marked_x_snapshot = _ever_marked_x
        _ever_marked_x = true
    else:
        if prev_state == CellState.MARK and _mark_entered_time_ms >= 0:
            if state == CellState.CAT:
                var mark_dur_ms: int = Time.get_ticks_msec() - _mark_entered_time_ms
                if mark_dur_ms < _DOUBLE_TAP_MARK_GRACE_MS:
                    _ever_marked_x = _ever_marked_x_snapshot
            _mark_entered_time_ms = -1
        if state == CellState.ERROR:
            _ever_marked_x = true
            _ever_errored = true

    if is_play_anim and not Engine.is_editor_hint() and appear_anim == "" and disappear_anim == "":
        _emit_state_sound(prev_state, state)

    if state == CellState.LOCKED_MARK:
        if lock_anim != "":
            _anim.stop()
            _anim.play(lock_anim)
            _anim.advance(0.0)
            if not is_play_anim:
                _anim.advance(_anim.current_animation_length)
        return

    if _preview_tween != null and _preview_tween.is_valid():
        _preview_tween.kill()
        _preview_tween = null

    _anim.stop()
    _anim.play("RESET")
    _anim.advance(0.0)

    _press_shrunk = false

    if state == CellState.CAT:
        _cat_cry_loop = false
        _cross.visible = false
        if not show_cat_visual:
            _set_particles_visible(false)
            return
        _set_particles_visible(is_play_anim)
        if is_play_anim:
            _anim.play("CatIconAppear")
        else:
            _anim.play("CatIconIdle")
            _anim.advance(_anim.current_animation_length)

            if _cat_icon != null:
                _cat_icon.modulate = Color(1, 1, 1, 1)
        _idle_timer.start()
        return

    _idle_timer.stop()
    _cat_cry_loop = false

    var anim_name := _get_anim_name(prev_state, state)

    if appear_anim != "":
        anim_name = appear_anim

    if disappear_anim != "" and prev_state == CellState.MARK and state == CellState.EMPTY:
        anim_name = disappear_anim

    if split_press and is_play_anim and state == CellState.MARK and anim_name == "CrossOutAppear":
        anim_name = "CrossOutAppearNoScale"
    elif (
        split_press
        and is_play_anim
        and state == CellState.EMPTY
        and anim_name == "CrossOutDisAppear"
    ):
        anim_name = "CrossOutDisAppearNoScale"

    _cross.visible = (
        anim_name == "CrossOutAppear"
        or anim_name == "CrossOutDisAppear"
        or anim_name == "AutomaticAppear"
        or anim_name == "AutomaticDisappear"
        or anim_name == "CrossOutAppearNoScale"
        or anim_name == "CrossOutDisAppearNoScale"
    )

    if anim_name == "":
        return
    _anim.play(anim_name)
    _anim.advance(0.0)
    if not is_play_anim:
        _anim.advance(_anim.current_animation_length)

    if anim_name == "CrossOutAppearNoScale" or anim_name == "CrossOutDisAppearNoScale":
        _scale_anim.stop()
        _scale_anim.play("PressShrink")
        _press_shrunk = true


func play_mark_release() -> void:
    if not _press_shrunk:
        return
    _press_shrunk = false
    _scale_anim.stop()
    _scale_anim.play("PressGrow")


func get_state() -> int:
    return _state


func preset_mark_for_auto_cross() -> void:
    if _state != CellState.EMPTY:
        return
    _state = CellState.MARK
    _mark_entered_time_ms = Time.get_ticks_msec()
    _ever_marked_x_snapshot = _ever_marked_x
    _ever_marked_x = true


func play_pending_auto_cross_appear() -> void:
    if _state != CellState.MARK:
        return
    if _cross.visible:
        return
    _cross.visible = true
    _anim.stop()
    _anim.play("AutomaticAppear")
    _anim.advance(0.0)


var _auto_mark_locked: bool = false


func set_auto_mark_locked(locked: bool) -> void:
    _auto_mark_locked = locked


func is_auto_mark_locked() -> bool:
    return _auto_mark_locked


func _is_draft_state(s: int) -> bool:
    return s == CellState.DRAFT_CROSS or s == CellState.DRAFT_CAT


func reset_clap_tracking() -> void:
    _ever_marked_x = false
    _ever_errored = false
    _mark_entered_time_ms = -1
    _ever_marked_x_snapshot = false


func has_ever_marked_x() -> bool:
    return _ever_marked_x


func has_ever_errored() -> bool:
    return _ever_errored


func _emit_state_sound(prev_state: int, state: int) -> void:
    if state == CellState.CAT:
        SoundManager.play(SoundManager.Kind.MARK_CAT)
    elif state == CellState.ERROR:
        if ABTestManager.wrong_cat_effect.should_lower_wrong_volume():
            SoundManager.play(SoundManager.Kind.MARK_WRONG_LOW)
        else:
            SoundManager.play(SoundManager.Kind.MARK_WRONG)
    elif state == CellState.MARK and prev_state == CellState.EMPTY:
        SoundManager.play(SoundManager.Kind.MARK_X)
    elif state == CellState.EMPTY and prev_state == CellState.MARK:
        SoundManager.play(SoundManager.Kind.UNMARK_X)


func _get_anim_name(prev: int, target: int) -> String:
    match target:
        CellState.EMPTY:
            return "CrossOutDisAppear" if prev == CellState.MARK else ""
        CellState.MARK:
            return "CrossOutAppear"
        CellState.ERROR:
            return _resolve_error_appear_anim()
        _:
            return ""


func _resolve_error_appear_anim() -> String:
    var no_red: bool = ABTestManager.wrong_cat_effect.should_skip_red_fill()
    var crash_val: int = ABTestManager.icon_crash.value() as int
    if no_red:
        if crash_val == IconCrashConfig.VALUE_NO_CRASH:
            return "ErrorAppear5"
        elif crash_val == IconCrashConfig.VALUE_FISH_CRASH:
            return "ErrorAppear4"
        return "ErrorAppear3"
    else:
        if crash_val == IconCrashConfig.VALUE_NO_CRASH:
            return "ErrorAppear1"
        elif crash_val == IconCrashConfig.VALUE_FISH_CRASH:
            return "ErrorAppear2"
        return "ErrorAppear"


func force_play_appear(with_particles: bool = true) -> void:
    _set_particles_visible(with_particles)
    _idle_timer.stop()
    _anim.stop()
    _anim.play("CatIconAppear")


func _set_particles_visible(show: bool) -> void:
    var fx: Control = get_node_or_null("EffectCatIconAppear2")
    if fx != null:
        fx.visible = show


func play_cry_loop() -> void:
    if _state != CellState.CAT or _cat_cry_loop:
        return
    _cat_cry_loop = true
    _idle_timer.stop()

    if _cat_icon != null:
        _cat_icon.modulate = Color(1, 1, 1, 1)
    _anim.play("CatIconCry")


func play_frustrated_once() -> void:
    if _state != CellState.CAT or _cat_cry_loop:
        return

    if _cat_icon != null:
        _cat_icon.modulate = Color(1, 1, 1, 1)
    _anim.play(_error_catface_anim())


func revive_to_idle() -> void:
    if _state != CellState.CAT:
        return
    _cat_cry_loop = false
    _anim.stop()
    _anim.play("CatIconIdle")
    _anim.advance(_anim.current_animation_length)
    _idle_timer.start()


func _on_anim_finished(anim_name: StringName) -> void:
    if _state != CellState.CAT:
        return
    if anim_name == "CatIconCry" and _cat_cry_loop:
        _anim.play("CatIconCry")
    elif anim_name == _error_catface_anim():
        _anim.play("CatIconIdle")
        if not _is_idle_anim_enabled():
            _anim.advance(_anim.current_animation_length)
    elif anim_name == "CatIconAppear":
        _anim.play("CatIconIdle")
        if not _is_idle_anim_enabled():
            _anim.advance(_anim.current_animation_length)


func _on_idle_timer_timeout() -> void:
    if _state != CellState.CAT or _cat_cry_loop:
        return
    if not _is_idle_anim_enabled():
        return
    var cur := _anim.current_animation
    if cur == "CatIconCry" or cur == _error_catface_anim():
        return
    _anim.play("CatIconIdle")


func _is_idle_anim_enabled() -> bool:
    if _demo_cat_no_idle:
        return false
    if ABTestManager == null or ABTestManager.play_anim == null:
        return true
    return ABTestManager.play_anim.is_idle_anim_enabled()


func _error_catface_anim() -> StringName:
    if ABTestManager == null or ABTestManager.error_catface == null:
        return &"CatIconFrustrated"
    return ABTestManager.error_catface.anim_for_error()


func _is_eliminate_shrink_cross() -> bool:
    if ABTestManager == null or ABTestManager.eliminate_effect == null:
        return false
    return ABTestManager.eliminate_effect.is_shrink_cross()


func _is_eliminate_remove_glow() -> bool:
    if ABTestManager == null or ABTestManager.eliminate_effect == null:
        return false
    return ABTestManager.eliminate_effect.is_remove_glow()


func play_hint() -> void:
    if _hint_tween != null and _hint_tween.is_valid():
        _hint_tween.kill()
    _hint_light.modulate.a = _HINT_ALPHA_MIN
    _hint_light.visible = true

    _prompt_frame.visible = true
    _prompt_frame.modulate.a = _HINT_ALPHA_MIN
    _hint_tween = create_tween()
    _hint_tween.set_loops()
    _hint_tween.tween_property(_hint_light, "modulate:a", 1.0, _HINT_HALF_CYCLE)
    _hint_tween.tween_property(_hint_light, "modulate:a", _HINT_ALPHA_MIN, _HINT_HALF_CYCLE)
    if _frame_tween != null and _frame_tween.is_valid():
        _frame_tween.kill()
    _frame_tween = create_tween()
    _frame_tween.set_loops()
    _frame_tween.tween_property(_prompt_frame, "modulate:a", 1.0, _HINT_HALF_CYCLE)
    _frame_tween.tween_property(_prompt_frame, "modulate:a", _HINT_ALPHA_MIN, _HINT_HALF_CYCLE)


func play_r2_preview(delay: float = 0.0) -> void:
    if _preview_tween != null and _preview_tween.is_valid():
        _preview_tween.kill()
    _preview_tween = create_tween()
    _preview_tween.set_parallel(true)
    _preview_tween.tween_property(_bg, "modulate:a", 1.0, 0.2)
    (
        _preview_tween
        . tween_callback(func() -> void: _anim.play("PromptCrossOut"))
        . set_delay(0.317 + delay)
    )


func play_prompt_cat(delay: float = 0.0) -> void:
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(_bg, "modulate:a", 1.0, 0.2)
    tw.tween_callback(
        func() -> void:
            _cat_prompt.visible = true
            _cat_prompt.modulate.a = 1.0
            _cat_prompt.scale = Vector2(0.3, 0.3)

            _prompt_frame.visible = true
            _prompt_frame.modulate.a = 1.0
            var tw2 := _cat_prompt.create_tween()
            tw2.tween_property(_cat_prompt, "scale", Vector2(1.0, 1.0), 0.25).set_ease(
                Tween.EASE_OUT
            ).set_trans(Tween.TRANS_BACK)
            tw2.tween_callback(
                func() -> void:
                    var tw3 := _cat_prompt.create_tween()
                    tw3.set_loops()
                    tw3.tween_property(_cat_prompt, "modulate:a", 0.5, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
                    tw3.tween_property(_cat_prompt, "modulate:a", 1.0, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
                    var tw4 := _prompt_frame.create_tween()
                    tw4.set_loops()
                    tw4.tween_property(_prompt_frame, "modulate:a", 0.6, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
                    tw4.tween_property(_prompt_frame, "modulate:a", 1.0, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
            )
    ).set_delay(delay)


func play_hide_hint() -> void:
    if _hint_tween != null and _hint_tween.is_valid():
        _hint_tween.kill()
        _hint_tween = null
    if _frame_tween != null and _frame_tween.is_valid():
        _frame_tween.kill()
        _frame_tween = null
    if _preview_tween != null and _preview_tween.is_valid():
        _preview_tween.kill()
        _preview_tween = null

    _cat_prompt.modulate.a = 1.0
    _cat_prompt.visible = false
    _prompt_frame.modulate.a = 1.0
    _prompt_frame.visible = false
    if _state != CellState.MARK and _state != CellState.ERROR and _state != CellState.CAT:
        _anim.play("RESET")
        _cross.visible = false
    if not _hint_light.visible:
        return
    _hint_tween = create_tween()
    _hint_tween.tween_property(_hint_light, "modulate:a", 0.0, _HINT_FADE_OUT)
    _hint_tween.tween_callback(func() -> void: _hint_light.visible = false)


signal undo_highlight_finished


func play_undo_highlight(_duration: float) -> void:
    pass


func stop_undo_highlight() -> void:
    pass


func _apply_draft_visual(state: int) -> void:
    match state:
        CellState.DRAFT_CROSS:
            _prompt_cross_out.visible = true
            _prompt_cross_out.scale = Vector2.ONE
            _prompt_cross_out.modulate = Color.WHITE
            if not _prompt_frame.visible:
                _cat_prompt.visible = false
        CellState.DRAFT_CAT:
            _prompt_cross_out.visible = false
            _cat_prompt.visible = true
            _cat_prompt.modulate = Color.WHITE
            _cat_prompt.scale = Vector2.ONE

        _:
            _prompt_cross_out.visible = false

            if not _prompt_frame.visible:
                _cat_prompt.visible = false


func play_draft_cross_disappear() -> void:
    if _state != CellState.DRAFT_CROSS:
        return

    _state = CellState.EMPTY
    _prompt_cross_out.visible = true
    _anim.stop()
    _anim.play("PromptCrossOutDisappear")


func play_draft_cross_apply() -> void:
    if _state != CellState.DRAFT_CROSS:
        return

    _state = CellState.MARK
    _ever_marked_x = true
    _mark_entered_time_ms = Time.get_ticks_msec()
    _anim.stop()
    _prompt_cross_out.visible = true
    _anim.play("PromptCrossOutDisappear")

    _anim.animation_finished.connect(
        func(anim_name: StringName) -> void:
            if anim_name == &"PromptCrossOutDisappear" and _state == CellState.MARK:
                _cross.visible = true
                _anim.play("CrossOutAppear2"),
        CONNECT_ONE_SHOT
    )


func demo_play(anim_name: String, instant: bool = false) -> void:
    _idle_timer.stop()
    _anim.stop()
    if anim_name.begins_with("CrossOut"):
        _cross.visible = true
    _anim.play(anim_name)
    if instant:
        _anim.advance(_anim.current_animation_length)


func demo_cat(animate: bool) -> void:
    _idle_timer.stop()
    _cat_cry_loop = false
    _demo_cat_no_idle = true
    _state = CellState.CAT
    _cross.visible = false
    _set_particles_visible(animate)
    _anim.stop()
    if animate:
        _anim.play("CatIconAppear")
    else:
        _anim.play("CatIconIdle")
        _anim.advance(_anim.current_animation_length)

        if _cat_icon != null:
            _cat_icon.modulate = Color(1, 1, 1, 1)


func demo_clear() -> void:
    _idle_timer.stop()
    _cat_cry_loop = false
    _demo_cat_no_idle = false
    _state = CellState.EMPTY
    _anim.stop()
    _anim.play("RESET")
    _anim.advance(0.0)
    _cross.visible = false


func demo_anim_length(anim_name: String) -> float:
    return _anim.get_animation(anim_name).length if _anim.has_animation(anim_name) else 0.0


func _update_bg() -> void:
    _style.bg_color = _region_color
