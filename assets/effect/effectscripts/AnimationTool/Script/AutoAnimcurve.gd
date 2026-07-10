@tool
extends Node
class_name AutoAnimCurve







enum EaseType{
    CUSTOM, 
    LINEAR, 
    SINE_IN, SINE_OUT, SINE_IN_OUT, 
    QUAD_IN, QUAD_OUT, QUAD_IN_OUT, 
    CUBIC_IN, CUBIC_OUT, CUBIC_IN_OUT, 
    QUART_IN, QUART_OUT, QUART_IN_OUT, 
    QUINT_IN, QUINT_OUT, QUINT_IN_OUT, 
    EXPO_IN, EXPO_OUT, EXPO_IN_OUT, 
    CIRC_IN, CIRC_OUT, CIRC_IN_OUT, 
    BACK_IN, BACK_OUT, BACK_IN_OUT, 
    ELASTIC_IN, ELASTIC_OUT, ELASTIC_IN_OUT, 
    BOUNCE_IN, BOUNCE_OUT, BOUNCE_IN_OUT, 
}




@export_group("预览 Preview")
@export_tool_button("▶  Preview") var _preview_btn: Callable = func(): _do_preview()
@export_tool_button("↩  Reset") var _reset_btn: Callable = func(): _do_reset()


@export var target_node: Node




@export_group("旋转 Rotation")
@export var rotation_enabled: bool = false
@export var rotation_duration: float = 0.5

@export var rotation_angle: float = 90.0
@export var rotation_curve: EaseType = EaseType.SINE_OUT
@export var rotation_custom_curve: Curve




@export_group("位移 Translation")
@export var translation_enabled: bool = false
@export var translation_duration: float = 0.5
@export var translation_offset_x: float = 0.0
@export var translation_offset_y: float = 0.0
@export var translation_curve_x: EaseType = EaseType.SINE_OUT
@export var translation_custom_curve_x: Curve
@export var translation_curve_y: EaseType = EaseType.SINE_OUT
@export var translation_custom_curve_y: Curve




@export_group("缩放 Scale")
@export var scale_enabled: bool = false
@export var scale_duration: float = 0.5

@export var scale_target_x: float = 1.0
@export var scale_target_y: float = 1.0
@export var scale_curve_x: EaseType = EaseType.SINE_OUT
@export var scale_custom_curve_x: Curve
@export var scale_curve_y: EaseType = EaseType.SINE_OUT
@export var scale_custom_curve_y: Curve




@export_group("透明度 Alpha")
@export var alpha_enabled: bool = false
@export var alpha_duration: float = 0.5

@export var alpha_target: float = 0.0
@export var alpha_curve: EaseType = EaseType.SINE_OUT
@export var alpha_custom_curve: Curve




var _origin_pos: Vector2 = Vector2.ZERO
var _origin_rot: float = 0.0
var _origin_scale: Vector2 = Vector2.ONE
var _origin_alpha: float = 1.0

var _elapsed: float = 0.0
var _max_dur: float = 0.0




func _ready() -> void :
    set_process(false)
    _cache_origin()

func _process(delta: float) -> void :
    _elapsed += delta
    _apply_all(minf(_elapsed, _max_dur))
    if _elapsed >= _max_dur:
        set_process(false)






func play() -> void :
    _cache_origin()
    _start()


func stop() -> void :
    set_process(false)
    _restore_origin()





func _do_preview() -> void :
    if not Engine.is_editor_hint() or not is_inside_tree():
        return

    _start()

func _do_reset() -> void :
    if not is_inside_tree():
        return
    set_process(false)
    _restore_origin()








func _target() -> Node:

    if target_node:
        return target_node

    var node: Node = self
    if node is Control or node is Node2D:
        return node
    return get_parent()





func _start() -> void :
    var d: = _max_duration()
    if d <= 0.0:
        return
    _elapsed = 0.0
    _max_dur = d
    set_process(true)

func _max_duration() -> float:
    var d: = 0.0
    if rotation_enabled: d = maxf(d, rotation_duration)
    if translation_enabled: d = maxf(d, translation_duration)
    if scale_enabled: d = maxf(d, scale_duration)
    if alpha_enabled: d = maxf(d, alpha_duration)
    return d

func _cache_origin() -> void :
    var p: = _target()
    if not p:
        return
    if p is Node2D:
        var n: = p as Node2D
        _origin_pos = n.position
        _origin_rot = n.rotation_degrees
        _origin_scale = n.scale
    elif p is Control:
        var c: = p as Control
        _origin_pos = c.position
        _origin_rot = c.rotation_degrees
        _origin_scale = c.scale
    if p is CanvasItem:
        _origin_alpha = (p as CanvasItem).modulate.a

func _restore_origin() -> void :
    var p: = _target()
    if not p:
        return
    if p is Node2D:
        var n: = p as Node2D
        n.position = _origin_pos
        n.rotation_degrees = _origin_rot
        n.scale = _origin_scale
    elif p is Control:
        var c: = p as Control
        c.position = _origin_pos
        c.rotation_degrees = _origin_rot
        c.scale = _origin_scale
    if p is CanvasItem:
        var col: Color = (p as CanvasItem).modulate
        col.a = _origin_alpha
        (p as CanvasItem).modulate = col





func _apply_all(elapsed: float) -> void :
    var p: = _target()
    if not p:
        return

    if rotation_enabled:
        var t: = _ease_t(clampf(elapsed / rotation_duration, 0.0, 1.0), 
                        rotation_curve, rotation_custom_curve)
        var rot: = lerpf(_origin_rot, _origin_rot + rotation_angle, t)
        if p is Node2D: (p as Node2D).rotation_degrees = rot
        elif p is Control: (p as Control).rotation_degrees = rot

    if translation_enabled:
        var tx: = _ease_t(clampf(elapsed / translation_duration, 0.0, 1.0), 
                        translation_curve_x, translation_custom_curve_x)
        var ty: = _ease_t(clampf(elapsed / translation_duration, 0.0, 1.0), 
                        translation_curve_y, translation_custom_curve_y)
        var pos: = Vector2(
            lerpf(_origin_pos.x, _origin_pos.x + translation_offset_x, tx), 
            lerpf(_origin_pos.y, _origin_pos.y + translation_offset_y, ty))
        if p is Node2D: (p as Node2D).position = pos
        elif p is Control: (p as Control).position = pos

    if scale_enabled:
        var tsx: = _ease_t(clampf(elapsed / scale_duration, 0.0, 1.0), 
                        scale_curve_x, scale_custom_curve_x)
        var tsy: = _ease_t(clampf(elapsed / scale_duration, 0.0, 1.0), 
                        scale_curve_y, scale_custom_curve_y)
        var scl: = Vector2(
            lerpf(_origin_scale.x, scale_target_x, tsx), 
            lerpf(_origin_scale.y, scale_target_y, tsy))
        if p is Node2D: (p as Node2D).scale = scl
        elif p is Control: (p as Control).scale = scl

    if alpha_enabled and p is CanvasItem:
        var ta: = _ease_t(clampf(elapsed / alpha_duration, 0.0, 1.0), 
                        alpha_curve, alpha_custom_curve)
        var col: Color = (p as CanvasItem).modulate
        col.a = lerpf(_origin_alpha, alpha_target, ta)
        (p as CanvasItem).modulate = col





func _ease_t(t: float, ease_type: EaseType, custom_curve: Curve) -> float:
    if ease_type == EaseType.CUSTOM and custom_curve != null:
        return custom_curve.sample(t)
    if ease_type == EaseType.LINEAR:
        return t
    return Tween.interpolate_value(
        0.0, 1.0, t, 1.0, _get_trans(ease_type), _get_ease(ease_type))

func _get_trans(ease_type: EaseType) -> Tween.TransitionType:
    match ease_type:
        EaseType.SINE_IN, EaseType.SINE_OUT, EaseType.SINE_IN_OUT:
            return Tween.TRANS_SINE
        EaseType.QUAD_IN, EaseType.QUAD_OUT, EaseType.QUAD_IN_OUT:
            return Tween.TRANS_QUAD
        EaseType.CUBIC_IN, EaseType.CUBIC_OUT, EaseType.CUBIC_IN_OUT:
            return Tween.TRANS_CUBIC
        EaseType.QUART_IN, EaseType.QUART_OUT, EaseType.QUART_IN_OUT:
            return Tween.TRANS_QUART
        EaseType.QUINT_IN, EaseType.QUINT_OUT, EaseType.QUINT_IN_OUT:
            return Tween.TRANS_QUINT
        EaseType.EXPO_IN, EaseType.EXPO_OUT, EaseType.EXPO_IN_OUT:
            return Tween.TRANS_EXPO
        EaseType.CIRC_IN, EaseType.CIRC_OUT, EaseType.CIRC_IN_OUT:
            return Tween.TRANS_CIRC
        EaseType.BACK_IN, EaseType.BACK_OUT, EaseType.BACK_IN_OUT:
            return Tween.TRANS_BACK
        EaseType.ELASTIC_IN, EaseType.ELASTIC_OUT, EaseType.ELASTIC_IN_OUT:
            return Tween.TRANS_ELASTIC
        EaseType.BOUNCE_IN, EaseType.BOUNCE_OUT, EaseType.BOUNCE_IN_OUT:
            return Tween.TRANS_BOUNCE
    return Tween.TRANS_LINEAR


func _get_ease(ease_type: EaseType) -> Tween.EaseType:
    var offset: = (ease_type - EaseType.SINE_IN) % 3
    match offset:
        1: return Tween.EASE_OUT
        2: return Tween.EASE_IN_OUT
        _: return Tween.EASE_IN
