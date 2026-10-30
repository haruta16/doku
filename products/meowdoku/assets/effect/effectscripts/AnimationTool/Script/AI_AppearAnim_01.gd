@tool
extends Node
class_name AI_AppearAnim_01

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
const _EASE_HINT := "CUSTOM,LINEAR,SINE_IN,SINE_OUT,SINE_IN_OUT,QUAD_IN,QUAD_OUT,QUAD_IN_OUT,CUBIC_IN,CUBIC_OUT,CUBIC_IN_OUT,QUART_IN,QUART_OUT,QUART_IN_OUT,QUINT_IN,QUINT_OUT,QUINT_IN_OUT,EXPO_IN,EXPO_OUT,EXPO_IN_OUT,CIRC_IN,CIRC_OUT,CIRC_IN_OUT,BACK_IN,BACK_OUT,BACK_IN_OUT,ELASTIC_IN,ELASTIC_OUT,ELASTIC_IN_OUT,BOUNCE_IN,BOUNCE_OUT,BOUNCE_IN_OUT"

signal intro_completed
signal outro_completed

var _intro_steps: Array[Dictionary] = []
var _outro_steps: Array[Dictionary] = []
var _intro_particle_steps: Array[Dictionary] = []
var _outro_particle_steps: Array[Dictionary] = []

@export_group("预览 Preview")

@export_tool_button("▶ 入场 Intro") var _btn_pi: Callable = func(): play_intro()

@export_tool_button("▶ 出场 Outro") var _btn_po: Callable = func(): play_outro()

@export_tool_button("↩ 复位 Reset") var _btn_rs: Callable = func(): reset_all()

@export_group("设置 Settings")

@export var auto_play_intro: bool = false

@export var auto_play_outro: bool = false

@export_group("入场 Intro")

@export var intro_step_count: int = 0:
	set(v):
		intro_step_count = clampi(v, 0, 32)
		_resize_steps(intro_step_count, _intro_steps)
		notify_property_list_changed()

@export_group("出场 Outro")

@export var outro_step_count: int = 0:
	set(v):
		outro_step_count = clampi(v, 0, 32)
		_resize_steps(outro_step_count, _outro_steps)
		notify_property_list_changed()

@export_group("入场粒子 Intro Particle")

@export var intro_particle_step_count: int = 0:
	set(v):
		intro_particle_step_count = clampi(v, 0, 32)
		_resize_particle_steps(intro_particle_step_count, _intro_particle_steps)
		notify_property_list_changed()

@export_group("出场粒子 Outro Particle")

@export var outro_particle_step_count: int = 0:
	set(v):
		outro_particle_step_count = clampi(v, 0, 32)
		_resize_particle_steps(outro_particle_step_count, _outro_particle_steps)
		notify_property_list_changed()


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	for i in intro_step_count:
		props.append_array(_step_props("i", i, "入场"))
	for i in outro_step_count:
		props.append_array(_step_props("o", i, "出场"))
	for i in intro_particle_step_count:
		props.append_array(_particle_step_props("pi", i, "入场粒子"))
	for i in outro_particle_step_count:
		props.append_array(_particle_step_props("po", i, "出场粒子"))
	return props


func _step_props(phase: String, i: int, label: String) -> Array[Dictionary]:
	var p := "%s%d_" % [phase, i]
	var props: Array[Dictionary] = []
	props.append(
		{
			"name": "%s 步骤 %d" % [label, i + 1],
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP,
			"hint_string": p
		}
	)
	props.append(
		_p("%sNotes" % p, TYPE_STRING, PROPERTY_HINT_NONE, "", "该步骤的备注说明，不影响任何动画逻辑，仅用于配置时标注用途")
	)
	props.append(_pnode("%starget" % p, "执行动画的目标节点（Node2D 或 Control），为空时跳过该步骤"))
	props.append(
		_p(
			"%sstart" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,30,0.01,suffix:s",
			"步骤在序列中的绝对起始时间（秒），从 play_intro / play_outro 调用时刻开始计算"
		)
	)
	props.append(
		{
			"name": "旋转 Rotation",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_EDITOR,
			"hint_string": "%srot_" % p
		}
	)
	props.append(_p("%srot_enabled" % p, TYPE_BOOL, PROPERTY_HINT_NONE, "", "启用旋转动画效果"))
	props.append(
		_p(
			"%srot_delay" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,10,0.01,suffix:s",
			"旋转动画在 start 之后的额外等待时间（秒）"
		)
	)
	props.append(
		_p(
			"%srot_duration" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0.01,10,0.01,suffix:s",
			"旋转动画的持续时长（秒）"
		)
	)
	props.append(
		_p(
			"%srot_ease" % p,
			TYPE_INT,
			PROPERTY_HINT_ENUM,
			_EASE_HINT,
			"旋转缓动类型；选 CUSTOM 后使用下方 Curve 自定义曲线"
		)
	)
	props.append(
		_p(
			"%srot_curve" % p,
			TYPE_OBJECT,
			PROPERTY_HINT_RESOURCE_TYPE,
			"Curve",
			"自定义旋转缓动曲线（仅 EaseType = CUSTOM 时生效）"
		)
	)
	props.append(
		_p(
			"%srot_from" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"-360,360,0.1,suffix:°",
			"旋转起始角度（度），入场从此角度开始，出场结束于此角度"
		)
	)
	props.append(
		_p(
			"%srot_to" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"-360,360,0.1,suffix:°",
			"旋转结束角度（度），入场结束于此角度，出场从此角度开始"
		)
	)
	props.append(
		{
			"name": "位移 Translation",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_EDITOR,
			"hint_string": "%str_" % p
		}
	)
	props.append(_p("%str_enabled" % p, TYPE_BOOL, PROPERTY_HINT_NONE, "", "启用位移动画效果"))
	props.append(
		_p(
			"%str_delay" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,10,0.01,suffix:s",
			"位移动画在 start 之后的额外等待时间（秒）"
		)
	)
	props.append(
		_p(
			"%str_duration" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0.01,10,0.01,suffix:s",
			"位移动画的持续时长（秒）"
		)
	)
	props.append(
		_p(
			"%str_ease" % p,
			TYPE_INT,
			PROPERTY_HINT_ENUM,
			_EASE_HINT,
			"位移缓动类型；选 CUSTOM 后使用下方 Curve 自定义曲线"
		)
	)
	props.append(
		_p(
			"%str_curve" % p,
			TYPE_OBJECT,
			PROPERTY_HINT_RESOURCE_TYPE,
			"Curve",
			"自定义位移缓动曲线（仅 EaseType = CUSTOM 时生效）"
		)
	)
	props.append(
		_p("%str_from" % p, TYPE_VECTOR2, PROPERTY_HINT_NONE, "", "位移起始偏移量（相对节点自然位置的 Vector2 偏移）")
	)
	props.append(
		_p(
			"%str_to" % p,
			TYPE_VECTOR2,
			PROPERTY_HINT_NONE,
			"",
			"位移结束偏移量（相对节点自然位置，通常为 (0, 0) 表示回到原位）"
		)
	)
	props.append(
		{
			"name": "缩放 Scale",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_EDITOR,
			"hint_string": "%ssc_" % p
		}
	)
	props.append(_p("%ssc_enabled" % p, TYPE_BOOL, PROPERTY_HINT_NONE, "", "启用缩放动画效果"))
	props.append(
		_p(
			"%ssc_delay" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,10,0.01,suffix:s",
			"缩放动画在 start 之后的额外等待时间（秒）"
		)
	)
	props.append(
		_p(
			"%ssc_duration" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0.01,10,0.01,suffix:s",
			"缩放动画的持续时长（秒）"
		)
	)
	props.append(
		_p(
			"%ssc_ease" % p,
			TYPE_INT,
			PROPERTY_HINT_ENUM,
			_EASE_HINT,
			"缩放缓动类型；选 CUSTOM 后使用下方 Curve 自定义曲线"
		)
	)
	props.append(
		_p(
			"%ssc_curve" % p,
			TYPE_OBJECT,
			PROPERTY_HINT_RESOURCE_TYPE,
			"Curve",
			"自定义缩放缓动曲线（仅 EaseType = CUSTOM 时生效）"
		)
	)
	props.append(
		_p("%ssc_from" % p, TYPE_VECTOR2, PROPERTY_HINT_NONE, "", "缩放起始比例，如 (0.8, 0.8) 表示从 80% 开始")
	)
	props.append(
		_p("%ssc_to" % p, TYPE_VECTOR2, PROPERTY_HINT_NONE, "", "缩放结束比例，如 (1.0, 1.0) 表示恢复原始大小")
	)
	props.append(
		_p(
			"%ssc_center_pivot" % p,
			TYPE_BOOL,
			PROPERTY_HINT_NONE,
			"",
			"自动将 Control 节点的 pivot_offset 设为中心，使缩放以中心为原点（Node2D 不受影响）"
		)
	)
	props.append(
		{
			"name": "透明度 Alpha",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_EDITOR,
			"hint_string": "%sal_" % p
		}
	)
	props.append(_p("%sal_enabled" % p, TYPE_BOOL, PROPERTY_HINT_NONE, "", "启用透明度动画效果"))
	props.append(
		_p(
			"%sal_delay" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,10,0.01,suffix:s",
			"透明度动画在 start 之后的额外等待时间（秒）"
		)
	)
	props.append(
		_p(
			"%sal_duration" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0.01,10,0.01,suffix:s",
			"透明度动画的持续时长（秒）"
		)
	)
	props.append(
		_p(
			"%sal_ease" % p,
			TYPE_INT,
			PROPERTY_HINT_ENUM,
			_EASE_HINT,
			"透明度缓动类型；选 CUSTOM 后使用下方 Curve 自定义曲线"
		)
	)
	props.append(
		_p(
			"%sal_curve" % p,
			TYPE_OBJECT,
			PROPERTY_HINT_RESOURCE_TYPE,
			"Curve",
			"自定义透明度缓动曲线（仅 EaseType = CUSTOM 时生效）"
		)
	)
	props.append(
		_p(
			"%sal_from" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,1,0.01",
			"透明度起始值（0 = 全透明，1 = 完全不透明）"
		)
	)
	props.append(
		_p("%sal_to" % p, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1,0.01", "透明度结束值（0 = 全透明，1 = 完全不透明）")
	)
	return props


func _particle_step_props(phase: String, i: int, label: String) -> Array[Dictionary]:
	var p := "%s%d_" % [phase, i]
	var props: Array[Dictionary] = []
	props.append(
		{
			"name": "%s 步骤 %d" % [label, i + 1],
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP,
			"hint_string": p
		}
	)
	props.append(_p("%sNotes" % p, TYPE_STRING, PROPERTY_HINT_NONE, "", "该粒子步骤的备注说明，不影响任何逻辑"))
	props.append(_pnode("%starget" % p, "目标粒子节点（GPUParticles2D 或 CPUParticles2D）；其他类型节点会被忽略"))
	props.append(
		_p(
			"%sstart" % p,
			TYPE_FLOAT,
			PROPERTY_HINT_RANGE,
			"0,30,0.01,suffix:s",
			"触发时间点（秒）：入场时激活粒子（emitting=true），出场时关闭粒子（emitting=false）"
		)
	)
	return props


func _p(
	pname: String,
	type: int,
	hint: int = PROPERTY_HINT_NONE,
	hint_str: String = "",
	desc: String = ""
) -> Dictionary:
	var d := {
		"name": pname,
		"type": type,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": hint,
		"hint_string": hint_str
	}
	if desc:
		d["description"] = desc
	return d


func _pnode(pname: String, desc: String = "") -> Dictionary:
	var d := {
		"name": pname,
		"type": TYPE_OBJECT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_NODE_TYPE,
		"hint_string": "Node",
		"class_name": &"Node"
	}
	if desc:
		d["description"] = desc
	return d


func _get(property: StringName) -> Variant:
	return _step_get(str(property))


func _set(property: StringName, value: Variant) -> bool:
	return _step_set(str(property), value)


func _step_get(s: String) -> Variant:
	var arr: Variant = _arr_for(s)
	if arr == null:
		return null
	var idx := _parse_idx(s)
	if idx >= (arr as Array).size():
		return null
	return (arr as Array)[idx].get(s.substr(s.find("_") + 1))


func _step_set(s: String, value: Variant) -> bool:
	var arr: Variant = _arr_for(s)
	if arr == null:
		return false
	var idx := _parse_idx(s)
	if idx >= (arr as Array).size():
		return false
	(arr as Array)[idx][s.substr(s.find("_") + 1)] = value
	return true


func _parse_idx(s: String) -> int:
	var u := s.find("_")
	var j := u - 1
	while j > 0 and s[j].is_valid_int():
		j -= 1
	return s.substr(j + 1, u - j - 1).to_int()


func _arr_for(s: String) -> Variant:
	var u := s.find("_")
	if u < 2:
		return null
	var j := u - 1
	while j > 0 and s[j].is_valid_int():
		j -= 1
	var phase := s.substr(0, j + 1)
	if not s.substr(j + 1, u - j - 1).is_valid_int():
		return null
	match phase:
		"i":
			return _intro_steps
		"o":
			return _outro_steps
		"pi":
			return _intro_particle_steps
		"po":
			return _outro_particle_steps
	return null


func _property_can_revert(property: StringName) -> bool:
	return _arr_for(str(property)) != null


func _property_get_revert(property: StringName) -> Variant:
	var s := str(property)
	var key := s.substr(s.find("_") + 1)
	if s.begins_with("pi") or s.begins_with("po"):
		return _default_particle_step().get(key)
	return _default_step().get(key)


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return
	if auto_play_intro:
		play_intro()
	if auto_play_outro:
		var p := get_parent()
		if p is CanvasItem:
			(p as CanvasItem).hidden.connect(play_outro, CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	_elapsed += delta
	var all_done := true
	for i in _active_steps.size():
		var st: Dictionary = _active_steps[i]
		var start: float = st.get("start", 0.0)
		var eff: float = _elapsed - start
		if eff < 0.0:
			all_done = false
			continue
		var n: Node = _resolve_node(st)
		if not n:
			continue
		if not _tick_step(n, st, eff):
			all_done = false
	for i in _active_particle_steps.size():
		var st: Dictionary = _active_particle_steps[i]
		if st.get("_triggered", false):
			continue
		var eff: float = _elapsed - st.get("start", 0.0)
		if eff < 0.0:
			all_done = false
			continue
		var n: Node = _resolve_node(st)
		if n:
			_trigger_particle(n, _is_intro)
		st["_triggered"] = true
	if all_done:
		set_process(false)
		_finish()


func play_intro() -> void:
	_play(_intro_steps, true)


func play_outro() -> void:
	_play(_outro_steps, false)


func stop() -> void:
	set_process(false)
	_playing = false


func is_playing() -> bool:
	return _playing


func reset_all() -> void:
	stop()
	for st in _intro_steps + _outro_steps:
		var n: Node = _resolve_node(st)
		if n:
			_apply_natural(n, _naturals.get(n.get_instance_id(), {}))
	for st in _intro_particle_steps + _outro_particle_steps:
		var n: Node = _resolve_node(st)
		if n:
			_trigger_particle(n, false)


var _playing: bool = false
var _is_intro: bool = true
var _elapsed: float = 0.0
var _naturals: Dictionary = {}
var _active_steps: Array = []
var _active_particle_steps: Array = []


func _play(steps: Array, is_intro: bool) -> void:
	stop()
	var p_steps := _intro_particle_steps if is_intro else _outro_particle_steps
	if steps.is_empty() and p_steps.is_empty():
		push_warning("[%s] step_count=0，请先配置步骤" % name)
		return
	var has_valid := false
	for st in steps:
		if _resolve_node(st) != null:
			has_valid = true
			break
	if not has_valid:
		for st in p_steps:
			if _resolve_node(st) != null:
				has_valid = true
				break
	if not has_valid:
		push_warning("[%s] 所有步骤的 target 均为空，动画无效果" % name)
	_is_intro = is_intro
	_playing = true
	_elapsed = 0.0
	for st in steps:
		var n: Node = _resolve_node(st)
		if n:
			_cache_natural(n)
	for st in steps:
		var n: Node = _resolve_node(st)
		if n:
			_apply_from_state(n, st)
	_active_steps = steps.duplicate()
	_active_particle_steps.clear()
	for st in p_steps:
		var copy := st.duplicate()
		copy["_triggered"] = false
		_active_particle_steps.append(copy)
	set_process(true)


func _finish() -> void:
	_playing = false
	_active_steps.clear()
	_active_particle_steps.clear()
	if _is_intro:
		intro_completed.emit()
	else:
		outro_completed.emit()


func _tick_step(node: Node, st: Dictionary, eff: float) -> bool:
	var done := true

	if st.get("rot_enabled", false):
		var del: float = st.get("rot_delay", 0.0)
		var dur: float = st.get("rot_duration", 0.5)
		var e: float = eff - del
		if e < 0.0:
			done = false
		else:
			var t := clampf(e / maxf(dur, 0.001), 0.0, 1.0)
			var rot := lerpf(
				st.get("rot_from", 0.0),
				st.get("rot_to", 0.0),
				_et(t, st.get("rot_ease", EaseType.SINE_OUT), st.get("rot_curve"))
			)
			if node is Node2D:
				(node as Node2D).rotation_degrees = rot
			elif node is Control:
				(node as Control).rotation_degrees = rot
			if e < dur:
				done = false

	if st.get("tr_enabled", false):
		var del: float = st.get("tr_delay", 0.0)
		var dur: float = st.get("tr_duration", 0.5)
		var e: float = eff - del
		if e < 0.0:
			done = false
		else:
			var t := clampf(e / maxf(dur, 0.001), 0.0, 1.0)
			var nat: Vector2 = _naturals.get(node.get_instance_id(), {}).get("pos", Vector2.ZERO)
			var f: Vector2 = st.get("tr_from", Vector2(0, 60))
			var to: Vector2 = st.get("tr_to", Vector2.ZERO)
			var off := f.lerp(to, _et(t, st.get("tr_ease", EaseType.SINE_OUT), st.get("tr_curve")))
			if node is Node2D:
				(node as Node2D).position = nat + off
			elif node is Control:
				(node as Control).position = nat + off
			if e < dur:
				done = false

	if st.get("sc_enabled", false):
		var del: float = st.get("sc_delay", 0.0)
		var dur: float = st.get("sc_duration", 0.5)
		var e: float = eff - del
		if e < 0.0:
			done = false
		else:
			if st.get("sc_center_pivot", true) and node is Control:
				(node as Control).pivot_offset = (node as Control).size / 2.0
			var t := clampf(e / maxf(dur, 0.001), 0.0, 1.0)
			var f: Vector2 = st.get("sc_from", Vector2(0.8, 0.8))
			var to: Vector2 = st.get("sc_to", Vector2.ONE)
			var scl := f.lerp(to, _et(t, st.get("sc_ease", EaseType.BACK_OUT), st.get("sc_curve")))
			if node is Node2D:
				(node as Node2D).scale = scl
			elif node is Control:
				(node as Control).scale = scl
			if e < dur:
				done = false

	if st.get("al_enabled", false) and node is CanvasItem:
		var del: float = st.get("al_delay", 0.0)
		var dur: float = st.get("al_duration", 0.5)
		var e: float = eff - del
		if e < 0.0:
			done = false
		else:
			var t := clampf(e / maxf(dur, 0.001), 0.0, 1.0)
			var col: Color = (node as CanvasItem).modulate
			col.a = lerpf(
				st.get("al_from", 0.0),
				st.get("al_to", 1.0),
				_et(t, st.get("al_ease", EaseType.SINE_OUT), st.get("al_curve"))
			)
			(node as CanvasItem).modulate = col
			if e < dur:
				done = false

	return done


func _cache_natural(node: Node) -> void:
	var id := node.get_instance_id()
	if _naturals.has(id):
		return
	var d: Dictionary = {}
	if node is Node2D:
		d = {
			"pos": (node as Node2D).position,
			"rot": (node as Node2D).rotation_degrees,
			"scale": (node as Node2D).scale
		}
	elif node is Control:
		d = {
			"pos": (node as Control).position,
			"rot": (node as Control).rotation_degrees,
			"scale": (node as Control).scale
		}
	if node is CanvasItem:
		d["alpha"] = (node as CanvasItem).modulate.a
	_naturals[id] = d


func _apply_from_state(node: Node, st: Dictionary) -> void:
	if not node or not is_instance_valid(node):
		return
	var nat: Dictionary = _naturals.get(node.get_instance_id(), {})
	_apply_natural(node, nat)
	if st.get("rot_enabled", false):
		var rot: float = st.get("rot_from", 0.0)
		if node is Node2D:
			(node as Node2D).rotation_degrees = rot
		elif node is Control:
			(node as Control).rotation_degrees = rot
	if st.get("tr_enabled", false):
		var nat_pos: Vector2 = nat.get("pos", Vector2.ZERO)
		var off: Vector2 = st.get("tr_from", Vector2(0, 60))
		if node is Node2D:
			(node as Node2D).position = nat_pos + off
		elif node is Control:
			(node as Control).position = nat_pos + off
	if st.get("sc_enabled", false):
		if st.get("sc_center_pivot", true) and node is Control:
			(node as Control).pivot_offset = (node as Control).size / 2.0
		var scl: Vector2 = st.get("sc_from", Vector2(0.8, 0.8))
		if node is Node2D:
			(node as Node2D).scale = scl
		elif node is Control:
			(node as Control).scale = scl
	if st.get("al_enabled", false) and node is CanvasItem:
		var col: Color = (node as CanvasItem).modulate
		col.a = st.get("al_from", 0.0)
		(node as CanvasItem).modulate = col


func _apply_natural(node: Node, nat: Dictionary) -> void:
	if not node or not is_instance_valid(node) or nat.is_empty():
		return
	if node is Node2D:
		(node as Node2D).position = nat.get("pos", Vector2.ZERO)
		(node as Node2D).rotation_degrees = nat.get("rot", 0.0)
		(node as Node2D).scale = nat.get("scale", Vector2.ONE)
	elif node is Control:
		(node as Control).position = nat.get("pos", Vector2.ZERO)
		(node as Control).rotation_degrees = nat.get("rot", 0.0)
		(node as Control).scale = nat.get("scale", Vector2.ONE)
	if node is CanvasItem:
		var col: Color = (node as CanvasItem).modulate
		col.a = nat.get("alpha", 1.0)
		(node as CanvasItem).modulate = col


func _resolve_node(st: Dictionary) -> Node:
	var t = st.get("target")
	if t is Node and is_instance_valid(t as Node):
		return t as Node
	if t is NodePath and not (t as NodePath).is_empty():
		return get_node_or_null(t as NodePath)
	return null


func _resize_steps(n: int, arr: Array) -> void:
	while arr.size() < n:
		arr.append(_default_step())
	while arr.size() > n:
		arr.pop_back()


func _resize_particle_steps(n: int, arr: Array) -> void:
	while arr.size() < n:
		arr.append(_default_particle_step())
	while arr.size() > n:
		arr.pop_back()


func _default_particle_step() -> Dictionary:
	return {"target": null, "start": 0.0, "Notes": ""}


func _trigger_particle(node: Node, emitting: bool) -> void:
	if node is GPUParticles2D:
		(node as GPUParticles2D).emitting = emitting
	elif node is CPUParticles2D:
		(node as CPUParticles2D).emitting = emitting


func _default_step() -> Dictionary:
	return {
		"target": null,
		"start": 0.0,
		"Notes": "",
		"rot_enabled": false,
		"rot_delay": 0.0,
		"rot_duration": 0.5,
		"rot_ease": EaseType.SINE_OUT,
		"rot_curve": null,
		"rot_from": 0.0,
		"rot_to": 0.0,
		"tr_enabled": false,
		"tr_delay": 0.0,
		"tr_duration": 0.5,
		"tr_ease": EaseType.SINE_OUT,
		"tr_curve": null,
		"tr_from": Vector2(0, 60),
		"tr_to": Vector2.ZERO,
		"sc_enabled": false,
		"sc_delay": 0.0,
		"sc_duration": 0.5,
		"sc_ease": EaseType.BACK_OUT,
		"sc_curve": null,
		"sc_from": Vector2(0.8, 0.8),
		"sc_to": Vector2.ONE,
		"sc_center_pivot": true,
		"al_enabled": false,
		"al_delay": 0.0,
		"al_duration": 0.5,
		"al_ease": EaseType.SINE_OUT,
		"al_curve": null,
		"al_from": 0.0,
		"al_to": 1.0,
	}


func _et(raw_t: float, ease_type: Variant, cv: Variant) -> float:
	var et: int = ease_type if ease_type is int else EaseType.SINE_OUT
	if et == EaseType.CUSTOM and cv is Curve:
		return (cv as Curve).sample(raw_t)
	if et == EaseType.LINEAR:
		return raw_t
	return Tween.interpolate_value(0.0, 1.0, raw_t, 1.0, _trans(et), _edir(et))


static func _trans(et: int) -> Tween.TransitionType:
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


static func _edir(et: int) -> Tween.EaseType:
	match (et - EaseType.SINE_IN) % 3:
		1:
			return Tween.EASE_OUT
		2:
			return Tween.EASE_IN_OUT
		_:
			return Tween.EASE_IN
