@tool
extends Node
class_name AutoCommonAnim_01

enum EaseType {
	CUSTOM,
	LINEAR,
	SINE_IN,
	SINE_OUT,
	SINE_IN_OUT,
	QUAD_IN,
	QUAD_OUT,
	QUAD_IN_OUT,
	CUBIC_IN,
	CUBIC_OUT,
	CUBIC_IN_OUT,
	QUART_IN,
	QUART_OUT,
	QUART_IN_OUT,
	QUINT_IN,
	QUINT_OUT,
	QUINT_IN_OUT,
	EXPO_IN,
	EXPO_OUT,
	EXPO_IN_OUT,
	CIRC_IN,
	CIRC_OUT,
	CIRC_IN_OUT,
	BACK_IN,
	BACK_OUT,
	BACK_IN_OUT,
	ELASTIC_IN,
	ELASTIC_OUT,
	ELASTIC_IN_OUT,
	BOUNCE_IN,
	BOUNCE_OUT,
	BOUNCE_IN_OUT,
}

signal intro_completed
signal outro_completed

@export_group("目标 Target")

@export var target_node: Node

@export var auto_play_intro: bool = false

@export var auto_play_outro: bool = false

@export_group("预览 Preview")
@export_tool_button("▶ 入场 Intro") var _btn_i: Callable = func(): play_intro()
@export_tool_button("▶ 出场 Outro") var _btn_o: Callable = func(): play_outro()
@export_tool_button("↩ 复位 Reset") var _btn_r: Callable = func(): reset()

@export_group("入场 Intro")

@export_subgroup("通用")

@export var intro_delay: float = 0.0

@export_subgroup("旋转 Rotation")

@export var intro_rot_enabled: bool = false

@export var intro_rot_delay: float = 0.0

@export var intro_rot_duration: float = 0.5

@export var intro_rot_ease: EaseType = EaseType.SINE_OUT

@export var intro_rot_curve: Curve

@export var intro_rot_from: float = -30.0

@export var intro_rot_to: float = 0.0

@export_subgroup("位移 Translation")

@export var intro_tr_enabled: bool = false

@export var intro_tr_delay: float = 0.0

@export var intro_tr_duration: float = 0.5

@export var intro_tr_ease: EaseType = EaseType.SINE_OUT

@export var intro_tr_curve: Curve

@export var intro_tr_from: Vector2 = Vector2(0.0, 60.0)

@export var intro_tr_to: Vector2 = Vector2.ZERO

@export_subgroup("缩放 Scale")

@export var intro_sc_enabled: bool = false

@export var intro_sc_delay: float = 0.0

@export var intro_sc_duration: float = 0.5

@export var intro_sc_ease: EaseType = EaseType.BACK_OUT

@export var intro_sc_curve: Curve

@export var intro_sc_from: Vector2 = Vector2(0.8, 0.8)

@export var intro_sc_to: Vector2 = Vector2.ONE

@export var intro_sc_center_pivot: bool = true

@export_subgroup("透明度 Alpha")

@export var intro_al_enabled: bool = false

@export var intro_al_delay: float = 0.0

@export var intro_al_duration: float = 0.5

@export var intro_al_ease: EaseType = EaseType.SINE_OUT

@export var intro_al_curve: Curve

@export var intro_al_from: float = 0.0

@export var intro_al_to: float = 1.0

@export_group("出场 Outro")

@export_subgroup("通用")

@export var outro_delay: float = 0.0

@export_subgroup("旋转 Rotation")

@export var outro_rot_enabled: bool = false

@export var outro_rot_delay: float = 0.0

@export var outro_rot_duration: float = 0.5

@export var outro_rot_ease: EaseType = EaseType.SINE_IN

@export var outro_rot_curve: Curve

@export var outro_rot_from: float = 0.0

@export var outro_rot_to: float = 30.0

@export_subgroup("位移 Translation")

@export var outro_tr_enabled: bool = false

@export var outro_tr_delay: float = 0.0

@export var outro_tr_duration: float = 0.5

@export var outro_tr_ease: EaseType = EaseType.SINE_IN

@export var outro_tr_curve: Curve

@export var outro_tr_from: Vector2 = Vector2.ZERO

@export var outro_tr_to: Vector2 = Vector2(0.0, 60.0)

@export_subgroup("缩放 Scale")

@export var outro_sc_enabled: bool = false

@export var outro_sc_delay: float = 0.0

@export var outro_sc_duration: float = 0.5

@export var outro_sc_ease: EaseType = EaseType.SINE_IN

@export var outro_sc_curve: Curve

@export var outro_sc_from: Vector2 = Vector2.ONE

@export var outro_sc_to: Vector2 = Vector2(0.8, 0.8)

@export var outro_sc_center_pivot: bool = true

@export_subgroup("透明度 Alpha")

@export var outro_al_enabled: bool = false

@export var outro_al_delay: float = 0.0

@export var outro_al_duration: float = 0.5

@export var outro_al_ease: EaseType = EaseType.SINE_IN

@export var outro_al_curve: Curve

@export var outro_al_from: float = 1.0

@export var outro_al_to: float = 0.0

enum _Phase { NONE, INTRO, OUTRO }
var _phase: _Phase = _Phase.NONE
var _elapsed: float = 0.0
var _natural_origin: Dictionary = {}
var _origins: Dictionary = {}

var _gd: float = 0.0
var _rot_en: bool = false
var _rot_d: float = 0.0
var _rot_dur: float = 0.5
var _rot_ease: EaseType = EaseType.SINE_OUT
var _rot_curve: Curve
var _rot_f: float = 0.0
var _rot_t: float = 0.0
var _tr_en: bool = false
var _tr_d: float = 0.0
var _tr_dur: float = 0.5
var _tr_ease: EaseType = EaseType.SINE_OUT
var _tr_curve: Curve
var _tr_f: Vector2 = Vector2.ZERO
var _tr_t: Vector2 = Vector2.ZERO
var _sc_en: bool = false
var _sc_d: float = 0.0
var _sc_dur: float = 0.5
var _sc_ease: EaseType = EaseType.SINE_OUT
var _sc_curve: Curve
var _sc_f: Vector2 = Vector2.ONE
var _sc_t: Vector2 = Vector2.ONE
var _sc_cp: bool = true
var _al_en: bool = false
var _al_d: float = 0.0
var _al_dur: float = 0.5
var _al_ease: EaseType = EaseType.SINE_OUT
var _al_curve: Curve
var _al_f: float = 1.0
var _al_t: float = 1.0


func _ready() -> void:
	set_process(false)

	_cache_origin()
	_natural_origin = _origins.duplicate()
	if Engine.is_editor_hint():
		return
	if auto_play_intro:
		play_intro()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and not Engine.is_editor_hint():
		if auto_play_outro:
			play_outro()


func _process(delta: float) -> void:
	_elapsed += delta
	var eff: float = _elapsed - _gd
	if eff < 0.0:
		return

	var done := true
	var node := _target()
	if not node:
		set_process(false)
		return

	if _rot_en:
		var t := _pt(eff, _rot_d, _rot_dur)
		var rot := lerpf(_rot_f, _rot_t, _et(t, _rot_ease, _rot_curve))
		if node is Node2D:
			(node as Node2D).rotation_degrees = rot
		elif node is Control:
			(node as Control).rotation_degrees = rot
		if eff < _rot_d + _rot_dur:
			done = false

	if _tr_en:
		var t := _pt(eff, _tr_d, _tr_dur)
		var origin: Vector2 = _origins.get("pos", Vector2.ZERO)
		var off := _tr_f.lerp(_tr_t, _et(t, _tr_ease, _tr_curve))
		if node is Node2D:
			(node as Node2D).position = origin + off
		elif node is Control:
			(node as Control).position = origin + off
		if eff < _tr_d + _tr_dur:
			done = false

	if _sc_en:
		if _sc_cp and node is Control:
			(node as Control).pivot_offset = (node as Control).size / 2.0
		var t := _pt(eff, _sc_d, _sc_dur)
		var scl := _sc_f.lerp(_sc_t, _et(t, _sc_ease, _sc_curve))
		if node is Node2D:
			(node as Node2D).scale = scl
		elif node is Control:
			(node as Control).scale = scl
		if eff < _sc_d + _sc_dur:
			done = false

	if _al_en and node is CanvasItem:
		var t := _pt(eff, _al_d, _al_dur)
		var col: Color = (node as CanvasItem).modulate
		col.a = lerpf(_al_f, _al_t, _et(t, _al_ease, _al_curve))
		(node as CanvasItem).modulate = col
		if eff < _al_d + _al_dur:
			done = false

	if done:
		set_process(false)
		_on_completed()


func play_intro() -> void:
	_snap(
		intro_delay,
		intro_rot_enabled,
		intro_rot_delay,
		intro_rot_duration,
		intro_rot_ease,
		intro_rot_curve,
		intro_rot_from,
		intro_rot_to,
		intro_tr_enabled,
		intro_tr_delay,
		intro_tr_duration,
		intro_tr_ease,
		intro_tr_curve,
		intro_tr_from,
		intro_tr_to,
		intro_sc_enabled,
		intro_sc_delay,
		intro_sc_duration,
		intro_sc_ease,
		intro_sc_curve,
		intro_sc_from,
		intro_sc_to,
		intro_sc_center_pivot,
		intro_al_enabled,
		intro_al_delay,
		intro_al_duration,
		intro_al_ease,
		intro_al_curve,
		intro_al_from,
		intro_al_to
	)
	_start(_Phase.INTRO)


func play_outro() -> void:
	_snap(
		outro_delay,
		outro_rot_enabled,
		outro_rot_delay,
		outro_rot_duration,
		outro_rot_ease,
		outro_rot_curve,
		outro_rot_from,
		outro_rot_to,
		outro_tr_enabled,
		outro_tr_delay,
		outro_tr_duration,
		outro_tr_ease,
		outro_tr_curve,
		outro_tr_from,
		outro_tr_to,
		outro_sc_enabled,
		outro_sc_delay,
		outro_sc_duration,
		outro_sc_ease,
		outro_sc_curve,
		outro_sc_from,
		outro_sc_to,
		outro_sc_center_pivot,
		outro_al_enabled,
		outro_al_delay,
		outro_al_duration,
		outro_al_ease,
		outro_al_curve,
		outro_al_from,
		outro_al_to
	)
	_start(_Phase.OUTRO)


func _apply_natural(node: Node) -> void:
	if not node or _natural_origin.is_empty():
		return
	if node is Node2D:
		(node as Node2D).position = _natural_origin.get("pos", Vector2.ZERO)
		(node as Node2D).rotation_degrees = _natural_origin.get("rot", 0.0)
		(node as Node2D).scale = _natural_origin.get("scale", Vector2.ONE)
	elif node is Control:
		(node as Control).position = _natural_origin.get("pos", Vector2.ZERO)
		(node as Control).rotation_degrees = _natural_origin.get("rot", 0.0)
		(node as Control).scale = _natural_origin.get("scale", Vector2.ONE)
	if node is CanvasItem:
		var col: Color = (node as CanvasItem).modulate
		col.a = _natural_origin.get("alpha", 1.0)
		(node as CanvasItem).modulate = col


func stop() -> void:
	set_process(false)
	_phase = _Phase.NONE


func reset() -> void:
	stop()
	_ensure_natural_origin()
	_apply_natural(_target())


func _snap(
	gd: float,
	rot_en: bool,
	rot_d: float,
	rot_dur: float,
	rot_ease: EaseType,
	rot_cv: Curve,
	rot_f: float,
	rot_t: float,
	tr_en: bool,
	tr_d: float,
	tr_dur: float,
	tr_ease: EaseType,
	tr_cv: Curve,
	tr_f: Vector2,
	tr_t: Vector2,
	sc_en: bool,
	sc_d: float,
	sc_dur: float,
	sc_ease: EaseType,
	sc_cv: Curve,
	sc_f: Vector2,
	sc_t: Vector2,
	sc_cp: bool,
	al_en: bool,
	al_d: float,
	al_dur: float,
	al_ease: EaseType,
	al_cv: Curve,
	al_f: float,
	al_t: float
) -> void:
	_gd = gd
	_rot_en = rot_en
	_rot_d = rot_d
	_rot_dur = rot_dur
	_rot_ease = rot_ease
	_rot_curve = rot_cv
	_rot_f = rot_f
	_rot_t = rot_t
	_tr_en = tr_en
	_tr_d = tr_d
	_tr_dur = tr_dur
	_tr_ease = tr_ease
	_tr_curve = tr_cv
	_tr_f = tr_f
	_tr_t = tr_t
	_sc_en = sc_en
	_sc_d = sc_d
	_sc_dur = sc_dur
	_sc_ease = sc_ease
	_sc_curve = sc_cv
	_sc_f = sc_f
	_sc_t = sc_t
	_sc_cp = sc_cp
	_al_en = al_en
	_al_d = al_d
	_al_dur = al_dur
	_al_ease = al_ease
	_al_curve = al_cv
	_al_f = al_f
	_al_t = al_t


func _start(phase: _Phase) -> void:
	stop()
	_ensure_natural_origin()
	_origins = _natural_origin.duplicate()
	_apply_natural(_target())
	_phase = phase
	_elapsed = 0.0
	set_process(true)


func _on_completed() -> void:
	var finished := _phase
	_phase = _Phase.NONE
	match finished:
		_Phase.INTRO:
			intro_completed.emit()
		_Phase.OUTRO:
			outro_completed.emit()


func _target() -> Node:
	if target_node and is_instance_valid(target_node):
		return target_node
	var s: Node = self
	if s is Control or s is Node2D:
		return s
	return get_parent()


func _ensure_natural_origin() -> void:
	if _natural_origin.is_empty():
		_cache_origin()
		_natural_origin = _origins.duplicate()


func _cache_origin() -> void:
	var node := _target()
	if not node:
		return
	if node is Node2D:
		_origins = {
			"pos": (node as Node2D).position,
			"rot": (node as Node2D).rotation_degrees,
			"scale": (node as Node2D).scale
		}
	elif node is Control:
		_origins = {
			"pos": (node as Control).position,
			"rot": (node as Control).rotation_degrees,
			"scale": (node as Control).scale
		}
	if node is CanvasItem:
		_origins["alpha"] = (node as CanvasItem).modulate.a


func _pt(eff: float, d: float, dur: float) -> float:
	return clampf((eff - d) / maxf(dur, 0.001), 0.0, 1.0)


func _et(raw_t: float, ease_type: EaseType, cv: Curve) -> float:
	if ease_type == EaseType.CUSTOM and cv != null:
		return cv.sample(raw_t)
	if ease_type == EaseType.LINEAR:
		return raw_t
	return Tween.interpolate_value(0.0, 1.0, raw_t, 1.0, _trans(ease_type), _edir(ease_type))


static func _trans(et: EaseType) -> Tween.TransitionType:
	match et:
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


static func _edir(et: EaseType) -> Tween.EaseType:
	var off := (et - EaseType.SINE_IN) % 3
	match off:
		1:
			return Tween.EASE_OUT
		2:
			return Tween.EASE_IN_OUT
		_:
			return Tween.EASE_IN
