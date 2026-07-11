@tool
extends Node
class_name BoardCellIntro

enum ActiveGroup { NONE, GROUP_1, GROUP_2, GROUP_3, GROUP_4 }

@export_group("目标 Target")
@export var board_view: Node:
	set(v):
		_disconnect_board_signals()
		board_view = v
		if not Engine.is_editor_hint() and auto_play:
			_connect_board_signals()

@export var auto_play: bool = true

@export var active_group: ActiveGroup = ActiveGroup.GROUP_1

@export_group("预览 Preview")
@export_tool_button("▶  Play") var _play_btn: Callable = func(): play()
@export_tool_button("↩  Reset") var _reset_btn: Callable = func(): reset()

@export_group("Group 1")

@export_subgroup("预设 Preset")
@export_file("*.cfg") var preset_path: String = "":
	set(v):
		preset_path = v.get_file() if not v.is_empty() else ""
@export_tool_button("📂 从预设加载") var _load_g1: Callable = func(): _load_from_file(ActiveGroup.GROUP_1)

@export_subgroup("父级 — 通用")
@export var list_delay: float = 0.0

@export_subgroup("父级 — 透明度 Alpha")
@export var container_fade_enabled: bool = false
@export var container_fade_duration: float = 0.5
@export var container_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var container_fade_custom_curve: Curve

@export_subgroup("父级 — 缩放 Scale")
@export var scale_enabled: bool = false
@export var scale_duration: float = 0.5
@export var scale_from: float = 0.85
@export var scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var scale_custom_curve: Curve

@export_subgroup("父级 — 位移 Translation")
@export var translation_enabled: bool = false
@export var translation_duration: float = 0.5
@export var translation_offset_x: float = 0.0
@export var translation_offset_y: float = 0.0
@export var translation_curve_x: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var translation_custom_curve_x: Curve
@export var translation_curve_y: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var translation_custom_curve_y: Curve

@export_subgroup("子集 — 通用")
@export var ring_interval: float = 0.2

@export_subgroup("子集 — 透明度 Alpha")
@export var cell_fade_duration: float = 0.3
@export var fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var fade_custom_curve: Curve

@export_subgroup("子集 — 缩放 Scale")
@export var cell_scale_enabled: bool = false
@export var cell_scale_duration: float = 0.3
@export var cell_scale_from: float = 0.7
@export var cell_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var cell_scale_custom_curve: Curve

@export_subgroup("应用")
@export_tool_button("💾 应用设置") var _g1_apply: Callable = func(): _apply_group(ActiveGroup.GROUP_1)
@export_tool_button("💾 应用设置(序号)")
var _g1_apply_n: Callable = func(): _apply_group_numbered(ActiveGroup.GROUP_1)

@export_group("Group 2")

@export_subgroup("预设 Preset")
@export_file("*.cfg") var g2_preset_path: String = "":
	set(v):
		g2_preset_path = v.get_file() if not v.is_empty() else ""
@export_tool_button("📂 从预设加载") var _load_g2: Callable = func(): _load_from_file(ActiveGroup.GROUP_2)

@export_subgroup("父级 — 通用")
@export var g2_list_delay: float = 0.0

@export_subgroup("父级 — 透明度 Alpha")
@export var g2_container_fade_enabled: bool = false
@export var g2_container_fade_duration: float = 0.5
@export var g2_container_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g2_container_fade_custom_curve: Curve

@export_subgroup("父级 — 缩放 Scale")
@export var g2_scale_enabled: bool = false
@export var g2_scale_duration: float = 0.5
@export var g2_scale_from: float = 0.85
@export var g2_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g2_scale_custom_curve: Curve

@export_subgroup("父级 — 位移 Translation")
@export var g2_translation_enabled: bool = false
@export var g2_translation_duration: float = 0.5
@export var g2_translation_offset_x: float = 0.0
@export var g2_translation_offset_y: float = 0.0
@export var g2_translation_curve_x: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g2_translation_custom_curve_x: Curve
@export var g2_translation_curve_y: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g2_translation_custom_curve_y: Curve

@export_subgroup("子集 — 通用")

@export var g2_row_interval: float = 0.15

@export_subgroup("子集 — 透明度 Alpha")
@export var g2_cell_fade_duration: float = 0.3
@export var g2_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g2_fade_custom_curve: Curve

@export_subgroup("子集 — 缩放 Scale")
@export var g2_cell_scale_enabled: bool = false
@export var g2_cell_scale_duration: float = 0.3
@export var g2_cell_scale_from: float = 0.7
@export var g2_cell_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g2_cell_scale_custom_curve: Curve

@export_subgroup("应用")
@export_tool_button("💾 应用设置") var _g2_apply: Callable = func(): _apply_group(ActiveGroup.GROUP_2)
@export_tool_button("💾 应用设置(序号)")
var _g2_apply_n: Callable = func(): _apply_group_numbered(ActiveGroup.GROUP_2)

@export_group("Group 3")

@export_subgroup("预设 Preset")
@export_file("*.cfg") var g3_preset_path: String = "":
	set(v):
		g3_preset_path = v.get_file() if not v.is_empty() else ""
@export_tool_button("📂 从预设加载") var _load_g3: Callable = func(): _load_from_file(ActiveGroup.GROUP_3)

@export_subgroup("父级 — 通用")
@export var g3_list_delay: float = 0.0

@export_subgroup("父级 — 透明度 Alpha")
@export var g3_container_fade_enabled: bool = false
@export var g3_container_fade_duration: float = 0.5
@export var g3_container_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_container_fade_custom_curve: Curve

@export_subgroup("父级 — 缩放 Scale")
@export var g3_scale_enabled: bool = false
@export var g3_scale_duration: float = 0.5
@export var g3_scale_from: float = 0.85
@export var g3_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g3_scale_custom_curve: Curve

@export_subgroup("父级 — 位移 Translation")
@export var g3_translation_enabled: bool = false
@export var g3_translation_duration: float = 0.5
@export var g3_translation_offset_x: float = 0.0
@export var g3_translation_offset_y: float = 0.0
@export var g3_translation_curve_x: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_translation_custom_curve_x: Curve
@export var g3_translation_curve_y: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_translation_custom_curve_y: Curve

@export_subgroup("子集 — 通用")

@export var g3_diag_interval: float = 0.12

@export_subgroup("子集 — 透明度 Alpha")
@export var g3_cell_fade_duration: float = 0.3
@export var g3_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_fade_custom_curve: Curve

@export_subgroup("子集 — 缩放 Scale")
@export var g3_cell_scale_enabled: bool = false
@export var g3_cell_scale_duration: float = 0.3
@export var g3_cell_scale_from: float = 0.7
@export var g3_cell_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g3_cell_scale_custom_curve: Curve

@export_subgroup("应用")
@export_tool_button("💾 应用设置") var _g3_apply: Callable = func(): _apply_group(ActiveGroup.GROUP_3)
@export_tool_button("💾 应用设置(序号)")
var _g3_apply_n: Callable = func(): _apply_group_numbered(ActiveGroup.GROUP_3)

@export_group("Group 4")

@export_subgroup("预设 Preset")
@export_file("*.cfg") var g4_preset_path: String = "":
	set(v):
		g4_preset_path = v.get_file() if not v.is_empty() else ""
@export_tool_button("📂 从预设加载") var _load_g4: Callable = func(): _load_from_file(ActiveGroup.GROUP_4)

@export_subgroup("父级 — 通用")
@export var g4_list_delay: float = 0.0

@export_subgroup("父级 — 透明度 Alpha")
@export var g4_container_fade_enabled: bool = false
@export var g4_container_fade_duration: float = 0.5
@export var g4_container_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g4_container_fade_custom_curve: Curve

@export_subgroup("父级 — 缩放 Scale")
@export var g4_scale_enabled: bool = false
@export var g4_scale_duration: float = 0.5
@export var g4_scale_from: float = 0.85
@export var g4_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g4_scale_custom_curve: Curve

@export_subgroup("父级 — 位移 Translation")
@export var g4_translation_enabled: bool = false
@export var g4_translation_duration: float = 0.5
@export var g4_translation_offset_x: float = 0.0
@export var g4_translation_offset_y: float = 0.0
@export var g4_translation_curve_x: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g4_translation_custom_curve_x: Curve
@export var g4_translation_curve_y: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g4_translation_custom_curve_y: Curve

@export_subgroup("子集 — 通用")

@export var g4_color_interval: float = 0.12

@export var g4_random_delay: float = 0.0

@export_subgroup("子集 — 透明度 Alpha")
@export var g4_cell_fade_duration: float = 0.3
@export var g4_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g4_fade_custom_curve: Curve

@export_subgroup("子集 — 缩放 Scale")
@export var g4_cell_scale_enabled: bool = false
@export var g4_cell_scale_duration: float = 0.3
@export var g4_cell_scale_from: float = 0.7
@export var g4_cell_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g4_cell_scale_custom_curve: Curve

@export_subgroup("应用")
@export_tool_button("💾 应用设置") var _g4_apply: Callable = func(): _apply_group(ActiveGroup.GROUP_4)
@export_tool_button("💾 应用设置(序号)")
var _g4_apply_n: Callable = func(): _apply_group_numbered(ActiveGroup.GROUP_4)

const _PRESET_DIR := "res://assets/effect/effectscripts/AnimationTool/Script/BoardCellIntro"

var _cells: Array = []
var _rings: Array = []
var _randoms: Array = []
var _elapsed: float = 0.0
var _origin_pos: Vector2 = Vector2.ZERO
var _param_hash: int = -1
var _play_scheduled: bool = false


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return

	_pre_hide_board()
	if auto_play:
		_connect_board_signals()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		var h := _get_param_hash()
		if h != _param_hash:
			play()
			return

	if active_group == ActiveGroup.NONE:
		set_process(false)
		return

	var p := _params()
	_elapsed += delta

	var fade_done := true
	var cell_scale_done := true
	for i in _cells.size():
		var cell: CanvasItem = _cells[i]
		if not is_instance_valid(cell):
			continue
		var t_start: float = (
			p.ld + _rings[i] * p.ri + (float(_randoms[i]) if i < _randoms.size() else 0.0)
		)

		if _elapsed < t_start + p.cfd:
			fade_done = false
		var fp := clampf((_elapsed - t_start) / maxf(p.cfd, 0.001), 0.0, 1.0)
		_set_alpha(cell, _ease_t(fp, p.fe, p.fcc))

		if p.cse:
			if _elapsed < t_start + p.csd:
				cell_scale_done = false
			var sp := clampf((_elapsed - t_start) / maxf(p.csd, 0.001), 0.0, 1.0)
			var s := lerpf(p.csf, 1.0, _ease_t(sp, p.csc, p.cscc))
			_set_scale(cell, Vector2(s, s))

	var container_fade_done := true
	if p.cfe and board_view and is_instance_valid(board_view):
		var cf_el := maxf(_elapsed - p.ld, 0.0)
		container_fade_done = cf_el >= p.cfdu
		var cfp := clampf(cf_el / maxf(p.cfdu, 0.001), 0.0, 1.0)
		_set_alpha(board_view as CanvasItem, _ease_t(cfp, p.cfea, p.cfcc))

	var scale_done := true
	if p.se and board_view and is_instance_valid(board_view):
		var s_el := maxf(_elapsed - p.ld, 0.0)
		scale_done = s_el >= p.sd
		var ts := clampf(s_el / maxf(p.sd, 0.001), 0.0, 1.0)
		var s := lerpf(p.sf, 1.0, _ease_t(ts, p.sc, p.scc))
		_set_scale(board_view, Vector2(s, s))

	var translation_done := true
	if p.te and board_view and is_instance_valid(board_view):
		var t_el := maxf(_elapsed - p.ld, 0.0)
		translation_done = t_el >= p.td
		var tx := clampf(t_el / maxf(p.td, 0.001), 0.0, 1.0)
		_set_position(
			board_view,
			Vector2(
				lerpf(_origin_pos.x + p.tox, _origin_pos.x, _ease_t(tx, p.tcx, p.tccx)),
				lerpf(_origin_pos.y + p.toy, _origin_pos.y, _ease_t(tx, p.tcy, p.tccy))
			)
		)

	if fade_done and cell_scale_done and container_fade_done and scale_done and translation_done:
		set_process(false)


func play() -> void:
	if active_group == ActiveGroup.NONE:
		return
	_build_cells()
	if _cells.is_empty():
		push_warning("BoardCellIntro.play(): board_view 子树中无 CellView 节点。")
		return
	_param_hash = _get_param_hash()
	if board_view and is_instance_valid(board_view):
		_origin_pos = _get_position(board_view)
	var p := _params()
	for cell in _cells:
		if not is_instance_valid(cell):
			continue
		_set_alpha(cell, 0.0)
		if p.cse:
			_set_scale(cell, Vector2(p.csf, p.csf))
	if board_view and is_instance_valid(board_view) and board_view is CanvasItem:
		_set_alpha(board_view as CanvasItem, 0.0 if p.cfe else 1.0)
	if p.se and board_view and is_instance_valid(board_view):
		_center_pivot(board_view)
		_set_scale(board_view, Vector2(p.sf, p.sf))
	if p.te and board_view and is_instance_valid(board_view):
		_set_position(board_view, _origin_pos + Vector2(p.tox, p.toy))
	_elapsed = 0.0
	set_process(true)


func reset() -> void:
	set_process(false)
	_build_cells()
	var p := _params()
	for cell in _cells:
		if not is_instance_valid(cell):
			continue
		_set_alpha(cell, 1.0)
		if p.cse:
			_set_scale(cell, Vector2.ONE)
	if board_view and is_instance_valid(board_view) and board_view is CanvasItem:
		_set_alpha(board_view as CanvasItem, 1.0)
		_set_scale(board_view, Vector2.ONE)
		_set_position(board_view, _origin_pos)


func _params() -> Dictionary:
	match active_group:
		ActiveGroup.GROUP_1:
			return {
				"ld": list_delay,
				"cfe": container_fade_enabled,
				"cfdu": container_fade_duration,
				"cfea": container_fade_ease,
				"cfcc": container_fade_custom_curve,
				"se": scale_enabled,
				"sd": scale_duration,
				"sf": scale_from,
				"sc": scale_curve,
				"scc": scale_custom_curve,
				"te": translation_enabled,
				"td": translation_duration,
				"tox": translation_offset_x,
				"toy": translation_offset_y,
				"tcx": translation_curve_x,
				"tccx": translation_custom_curve_x,
				"tcy": translation_curve_y,
				"tccy": translation_custom_curve_y,
				"ri": ring_interval,
				"cfd": cell_fade_duration,
				"fe": fade_ease,
				"fcc": fade_custom_curve,
				"cse": cell_scale_enabled,
				"csd": cell_scale_duration,
				"csf": cell_scale_from,
				"csc": cell_scale_curve,
				"cscc": cell_scale_custom_curve,
			}
		ActiveGroup.GROUP_2:
			return {
				"ld": g2_list_delay,
				"cfe": g2_container_fade_enabled,
				"cfdu": g2_container_fade_duration,
				"cfea": g2_container_fade_ease,
				"cfcc": g2_container_fade_custom_curve,
				"se": g2_scale_enabled,
				"sd": g2_scale_duration,
				"sf": g2_scale_from,
				"sc": g2_scale_curve,
				"scc": g2_scale_custom_curve,
				"te": g2_translation_enabled,
				"td": g2_translation_duration,
				"tox": g2_translation_offset_x,
				"toy": g2_translation_offset_y,
				"tcx": g2_translation_curve_x,
				"tccx": g2_translation_custom_curve_x,
				"tcy": g2_translation_curve_y,
				"tccy": g2_translation_custom_curve_y,
				"ri": g2_row_interval,
				"cfd": g2_cell_fade_duration,
				"fe": g2_fade_ease,
				"fcc": g2_fade_custom_curve,
				"cse": g2_cell_scale_enabled,
				"csd": g2_cell_scale_duration,
				"csf": g2_cell_scale_from,
				"csc": g2_cell_scale_curve,
				"cscc": g2_cell_scale_custom_curve,
			}
		ActiveGroup.GROUP_3:
			return {
				"ld": g3_list_delay,
				"cfe": g3_container_fade_enabled,
				"cfdu": g3_container_fade_duration,
				"cfea": g3_container_fade_ease,
				"cfcc": g3_container_fade_custom_curve,
				"se": g3_scale_enabled,
				"sd": g3_scale_duration,
				"sf": g3_scale_from,
				"sc": g3_scale_curve,
				"scc": g3_scale_custom_curve,
				"te": g3_translation_enabled,
				"td": g3_translation_duration,
				"tox": g3_translation_offset_x,
				"toy": g3_translation_offset_y,
				"tcx": g3_translation_curve_x,
				"tccx": g3_translation_custom_curve_x,
				"tcy": g3_translation_curve_y,
				"tccy": g3_translation_custom_curve_y,
				"ri": g3_diag_interval,
				"cfd": g3_cell_fade_duration,
				"fe": g3_fade_ease,
				"fcc": g3_fade_custom_curve,
				"cse": g3_cell_scale_enabled,
				"csd": g3_cell_scale_duration,
				"csf": g3_cell_scale_from,
				"csc": g3_cell_scale_curve,
				"cscc": g3_cell_scale_custom_curve,
			}
		ActiveGroup.GROUP_4:
			return {
				"ld": g4_list_delay,
				"cfe": g4_container_fade_enabled,
				"cfdu": g4_container_fade_duration,
				"cfea": g4_container_fade_ease,
				"cfcc": g4_container_fade_custom_curve,
				"se": g4_scale_enabled,
				"sd": g4_scale_duration,
				"sf": g4_scale_from,
				"sc": g4_scale_curve,
				"scc": g4_scale_custom_curve,
				"te": g4_translation_enabled,
				"td": g4_translation_duration,
				"tox": g4_translation_offset_x,
				"toy": g4_translation_offset_y,
				"tcx": g4_translation_curve_x,
				"tccx": g4_translation_custom_curve_x,
				"tcy": g4_translation_curve_y,
				"tccy": g4_translation_custom_curve_y,
				"ri": g4_color_interval,
				"cfd": g4_cell_fade_duration,
				"fe": g4_fade_ease,
				"fcc": g4_fade_custom_curve,
				"cse": g4_cell_scale_enabled,
				"csd": g4_cell_scale_duration,
				"csf": g4_cell_scale_from,
				"csc": g4_cell_scale_curve,
				"cscc": g4_cell_scale_custom_curve,
			}
	return {}


func _group_name() -> String:
	match active_group:
		ActiveGroup.GROUP_1:
			return "Group1"
		ActiveGroup.GROUP_2:
			return "Group2"
		ActiveGroup.GROUP_3:
			return "Group3"
		ActiveGroup.GROUP_4:
			return "Group4"
	return ""


func _group_preset_path() -> String:
	match active_group:
		ActiveGroup.GROUP_1:
			return preset_path
		ActiveGroup.GROUP_2:
			return g2_preset_path
		ActiveGroup.GROUP_3:
			return g3_preset_path
		ActiveGroup.GROUP_4:
			return g4_preset_path
	return ""


func _set_group_preset_path(fname: String) -> void:
	match active_group:
		ActiveGroup.GROUP_1:
			preset_path = fname
		ActiveGroup.GROUP_2:
			g2_preset_path = fname
		ActiveGroup.GROUP_3:
			g3_preset_path = fname
		ActiveGroup.GROUP_4:
			g4_preset_path = fname


func _apply_group(group: ActiveGroup) -> void:
	var saved := active_group
	active_group = group
	_apply_settings()
	active_group = saved


func _apply_group_numbered(group: ActiveGroup) -> void:
	var saved := active_group
	active_group = group
	_apply_settings_numbered()
	active_group = saved


func _apply_settings() -> void:
	var gname := _group_name()
	if gname.is_empty():
		push_warning("BoardCellIntro._apply_settings(): active_group 为 NONE，无参数可保存。")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_PRESET_DIR))
	var stored := _group_preset_path()
	var fname := stored if not stored.is_empty() else "BoardCellIntro_%s.cfg" % gname
	_save_cfg(fname, gname)


func _apply_settings_numbered() -> void:
	var gname := _group_name()
	if gname.is_empty():
		push_warning("BoardCellIntro._apply_settings_numbered(): active_group 为 NONE，无参数可保存。")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_PRESET_DIR))
	var next_n := 1
	var dir := DirAccess.open(_PRESET_DIR)
	if dir:
		var prefix := "BoardCellIntro_%s_" % gname
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.begins_with(prefix) and f.ends_with(".cfg"):
				var num_str := f.trim_prefix(prefix).trim_suffix(".cfg")
				if num_str.is_valid_int():
					next_n = max(next_n, num_str.to_int() + 1)
			f = dir.get_next()
		dir.list_dir_end()
	_save_cfg("BoardCellIntro_%s_%03d.cfg" % [gname, next_n], gname)


func _save_cfg(fname: String, section: String) -> void:
	var p := _params()
	var cfg := ConfigFile.new()
	cfg.set_value(section, "list_delay", p.ld)
	cfg.set_value(section, "container_fade_enabled", p.cfe)
	cfg.set_value(section, "container_fade_duration", p.cfdu)
	cfg.set_value(section, "container_fade_ease", int(p.cfea))
	cfg.set_value(section, "scale_enabled", p.se)
	cfg.set_value(section, "scale_duration", p.sd)
	cfg.set_value(section, "scale_from", p.sf)
	cfg.set_value(section, "scale_curve", int(p.sc))
	cfg.set_value(section, "translation_enabled", p.te)
	cfg.set_value(section, "translation_duration", p.td)
	cfg.set_value(section, "translation_offset_x", p.tox)
	cfg.set_value(section, "translation_offset_y", p.toy)
	cfg.set_value(section, "translation_curve_x", int(p.tcx))
	cfg.set_value(section, "translation_curve_y", int(p.tcy))
	var _ri_key: String
	match active_group:
		ActiveGroup.GROUP_2:
			_ri_key = "row_interval"
		ActiveGroup.GROUP_3:
			_ri_key = "diag_interval"
		ActiveGroup.GROUP_4:
			_ri_key = "color_interval"
		_:
			_ri_key = "ring_interval"
	cfg.set_value(section, _ri_key, p.ri)
	if active_group == ActiveGroup.GROUP_4:
		cfg.set_value(section, "random_delay", g4_random_delay)
	cfg.set_value(section, "cell_fade_duration", p.cfd)
	cfg.set_value(section, "fade_ease", int(p.fe))
	cfg.set_value(section, "cell_scale_enabled", p.cse)
	cfg.set_value(section, "cell_scale_duration", p.csd)
	cfg.set_value(section, "cell_scale_from", p.csf)
	cfg.set_value(section, "cell_scale_curve", int(p.csc))
	var save_path := _PRESET_DIR + "/" + fname
	var err := cfg.save(save_path)
	if err == OK:
		_set_group_preset_path(fname)
		print("BoardCellIntro: 参数已保存至 %s" % save_path)
	else:
		push_error("BoardCellIntro: 保存失败，错误码 %d" % err)


func _load_from_file(group: ActiveGroup = active_group) -> void:
	var old_group := active_group
	active_group = group
	var gname := _group_name()
	var stored := _group_preset_path()
	active_group = old_group
	if stored.is_empty():
		push_warning("BoardCellIntro: 请先在 %s 的「预设 Preset」中填写文件名。" % gname)
		return
	var full_path := _PRESET_DIR + "/" + stored
	var cfg := ConfigFile.new()
	var err := cfg.load(full_path)
	if err != OK:
		push_error("BoardCellIntro: 加载预设失败（错误码 %d）：%s" % [err, full_path])
		return
	_apply_cfg_to_group(cfg, gname, group)
	notify_property_list_changed()
	print("BoardCellIntro: 已从预设加载 %s → %s" % [full_path, gname])


func _apply_cfg_to_group(cfg: ConfigFile, section: String, group: ActiveGroup) -> void:
	match group:
		ActiveGroup.GROUP_1:
			list_delay = cfg.get_value(section, "list_delay", list_delay)
			container_fade_enabled = cfg.get_value(
				section, "container_fade_enabled", container_fade_enabled
			)
			container_fade_duration = cfg.get_value(
				section, "container_fade_duration", container_fade_duration
			)
			container_fade_ease = (
				cfg.get_value(section, "container_fade_ease", int(container_fade_ease))
				as AutoAnimCurve.EaseType
			)
			scale_enabled = cfg.get_value(section, "scale_enabled", scale_enabled)
			scale_duration = cfg.get_value(section, "scale_duration", scale_duration)
			scale_from = cfg.get_value(section, "scale_from", scale_from)
			scale_curve = (
				cfg.get_value(section, "scale_curve", int(scale_curve)) as AutoAnimCurve.EaseType
			)
			translation_enabled = cfg.get_value(section, "translation_enabled", translation_enabled)
			translation_duration = cfg.get_value(
				section, "translation_duration", translation_duration
			)
			translation_offset_x = cfg.get_value(
				section, "translation_offset_x", translation_offset_x
			)
			translation_offset_y = cfg.get_value(
				section, "translation_offset_y", translation_offset_y
			)
			translation_curve_x = (
				cfg.get_value(section, "translation_curve_x", int(translation_curve_x))
				as AutoAnimCurve.EaseType
			)
			translation_curve_y = (
				cfg.get_value(section, "translation_curve_y", int(translation_curve_y))
				as AutoAnimCurve.EaseType
			)
			ring_interval = cfg.get_value(section, "ring_interval", ring_interval)
			cell_fade_duration = cfg.get_value(section, "cell_fade_duration", cell_fade_duration)
			fade_ease = (
				cfg.get_value(section, "fade_ease", int(fade_ease)) as AutoAnimCurve.EaseType
			)
			cell_scale_enabled = cfg.get_value(section, "cell_scale_enabled", cell_scale_enabled)
			cell_scale_duration = cfg.get_value(section, "cell_scale_duration", cell_scale_duration)
			cell_scale_from = cfg.get_value(section, "cell_scale_from", cell_scale_from)
			cell_scale_curve = (
				cfg.get_value(section, "cell_scale_curve", int(cell_scale_curve))
				as AutoAnimCurve.EaseType
			)
		ActiveGroup.GROUP_2:
			g2_list_delay = cfg.get_value(section, "list_delay", g2_list_delay)
			g2_container_fade_enabled = cfg.get_value(
				section, "container_fade_enabled", g2_container_fade_enabled
			)
			g2_container_fade_duration = cfg.get_value(
				section, "container_fade_duration", g2_container_fade_duration
			)
			g2_container_fade_ease = (
				cfg.get_value(section, "container_fade_ease", int(g2_container_fade_ease))
				as AutoAnimCurve.EaseType
			)
			g2_scale_enabled = cfg.get_value(section, "scale_enabled", g2_scale_enabled)
			g2_scale_duration = cfg.get_value(section, "scale_duration", g2_scale_duration)
			g2_scale_from = cfg.get_value(section, "scale_from", g2_scale_from)
			g2_scale_curve = (
				cfg.get_value(section, "scale_curve", int(g2_scale_curve)) as AutoAnimCurve.EaseType
			)
			g2_translation_enabled = cfg.get_value(
				section, "translation_enabled", g2_translation_enabled
			)
			g2_translation_duration = cfg.get_value(
				section, "translation_duration", g2_translation_duration
			)
			g2_translation_offset_x = cfg.get_value(
				section, "translation_offset_x", g2_translation_offset_x
			)
			g2_translation_offset_y = cfg.get_value(
				section, "translation_offset_y", g2_translation_offset_y
			)
			g2_translation_curve_x = (
				cfg.get_value(section, "translation_curve_x", int(g2_translation_curve_x))
				as AutoAnimCurve.EaseType
			)
			g2_translation_curve_y = (
				cfg.get_value(section, "translation_curve_y", int(g2_translation_curve_y))
				as AutoAnimCurve.EaseType
			)
			g2_row_interval = cfg.get_value(section, "row_interval", g2_row_interval)
			g2_cell_fade_duration = cfg.get_value(
				section, "cell_fade_duration", g2_cell_fade_duration
			)
			g2_fade_ease = (
				cfg.get_value(section, "fade_ease", int(g2_fade_ease)) as AutoAnimCurve.EaseType
			)
			g2_cell_scale_enabled = cfg.get_value(
				section, "cell_scale_enabled", g2_cell_scale_enabled
			)
			g2_cell_scale_duration = cfg.get_value(
				section, "cell_scale_duration", g2_cell_scale_duration
			)
			g2_cell_scale_from = cfg.get_value(section, "cell_scale_from", g2_cell_scale_from)
			g2_cell_scale_curve = (
				cfg.get_value(section, "cell_scale_curve", int(g2_cell_scale_curve))
				as AutoAnimCurve.EaseType
			)
		ActiveGroup.GROUP_3:
			g3_list_delay = cfg.get_value(section, "list_delay", g3_list_delay)
			g3_container_fade_enabled = cfg.get_value(
				section, "container_fade_enabled", g3_container_fade_enabled
			)
			g3_container_fade_duration = cfg.get_value(
				section, "container_fade_duration", g3_container_fade_duration
			)
			g3_container_fade_ease = (
				cfg.get_value(section, "container_fade_ease", int(g3_container_fade_ease))
				as AutoAnimCurve.EaseType
			)
			g3_scale_enabled = cfg.get_value(section, "scale_enabled", g3_scale_enabled)
			g3_scale_duration = cfg.get_value(section, "scale_duration", g3_scale_duration)
			g3_scale_from = cfg.get_value(section, "scale_from", g3_scale_from)
			g3_scale_curve = (
				cfg.get_value(section, "scale_curve", int(g3_scale_curve)) as AutoAnimCurve.EaseType
			)
			g3_translation_enabled = cfg.get_value(
				section, "translation_enabled", g3_translation_enabled
			)
			g3_translation_duration = cfg.get_value(
				section, "translation_duration", g3_translation_duration
			)
			g3_translation_offset_x = cfg.get_value(
				section, "translation_offset_x", g3_translation_offset_x
			)
			g3_translation_offset_y = cfg.get_value(
				section, "translation_offset_y", g3_translation_offset_y
			)
			g3_translation_curve_x = (
				cfg.get_value(section, "translation_curve_x", int(g3_translation_curve_x))
				as AutoAnimCurve.EaseType
			)
			g3_translation_curve_y = (
				cfg.get_value(section, "translation_curve_y", int(g3_translation_curve_y))
				as AutoAnimCurve.EaseType
			)
			g3_diag_interval = cfg.get_value(section, "diag_interval", g3_diag_interval)
			g3_cell_fade_duration = cfg.get_value(
				section, "cell_fade_duration", g3_cell_fade_duration
			)
			g3_fade_ease = (
				cfg.get_value(section, "fade_ease", int(g3_fade_ease)) as AutoAnimCurve.EaseType
			)
			g3_cell_scale_enabled = cfg.get_value(
				section, "cell_scale_enabled", g3_cell_scale_enabled
			)
			g3_cell_scale_duration = cfg.get_value(
				section, "cell_scale_duration", g3_cell_scale_duration
			)
			g3_cell_scale_from = cfg.get_value(section, "cell_scale_from", g3_cell_scale_from)
			g3_cell_scale_curve = (
				cfg.get_value(section, "cell_scale_curve", int(g3_cell_scale_curve))
				as AutoAnimCurve.EaseType
			)
		ActiveGroup.GROUP_4:
			g4_list_delay = cfg.get_value(section, "list_delay", g4_list_delay)
			g4_container_fade_enabled = cfg.get_value(
				section, "container_fade_enabled", g4_container_fade_enabled
			)
			g4_container_fade_duration = cfg.get_value(
				section, "container_fade_duration", g4_container_fade_duration
			)
			g4_container_fade_ease = (
				cfg.get_value(section, "container_fade_ease", int(g4_container_fade_ease))
				as AutoAnimCurve.EaseType
			)
			g4_scale_enabled = cfg.get_value(section, "scale_enabled", g4_scale_enabled)
			g4_scale_duration = cfg.get_value(section, "scale_duration", g4_scale_duration)
			g4_scale_from = cfg.get_value(section, "scale_from", g4_scale_from)
			g4_scale_curve = (
				cfg.get_value(section, "scale_curve", int(g4_scale_curve)) as AutoAnimCurve.EaseType
			)
			g4_translation_enabled = cfg.get_value(
				section, "translation_enabled", g4_translation_enabled
			)
			g4_translation_duration = cfg.get_value(
				section, "translation_duration", g4_translation_duration
			)
			g4_translation_offset_x = cfg.get_value(
				section, "translation_offset_x", g4_translation_offset_x
			)
			g4_translation_offset_y = cfg.get_value(
				section, "translation_offset_y", g4_translation_offset_y
			)
			g4_translation_curve_x = (
				cfg.get_value(section, "translation_curve_x", int(g4_translation_curve_x))
				as AutoAnimCurve.EaseType
			)
			g4_translation_curve_y = (
				cfg.get_value(section, "translation_curve_y", int(g4_translation_curve_y))
				as AutoAnimCurve.EaseType
			)
			g4_color_interval = cfg.get_value(section, "color_interval", g4_color_interval)
			g4_random_delay = cfg.get_value(section, "random_delay", g4_random_delay)
			g4_cell_fade_duration = cfg.get_value(
				section, "cell_fade_duration", g4_cell_fade_duration
			)
			g4_fade_ease = (
				cfg.get_value(section, "fade_ease", int(g4_fade_ease)) as AutoAnimCurve.EaseType
			)
			g4_cell_scale_enabled = cfg.get_value(
				section, "cell_scale_enabled", g4_cell_scale_enabled
			)
			g4_cell_scale_duration = cfg.get_value(
				section, "cell_scale_duration", g4_cell_scale_duration
			)
			g4_cell_scale_from = cfg.get_value(section, "cell_scale_from", g4_cell_scale_from)
			g4_cell_scale_curve = (
				cfg.get_value(section, "cell_scale_curve", int(g4_cell_scale_curve))
				as AutoAnimCurve.EaseType
			)


func _connect_board_signals() -> void:
	if not board_view or not is_instance_valid(board_view):
		return
	_connect_one(board_view)
	for child in board_view.get_children():
		_connect_one(child)


func _disconnect_board_signals() -> void:
	if not board_view or not is_instance_valid(board_view):
		return
	_disconnect_one(board_view)
	for child in board_view.get_children():
		_disconnect_one(child)


func _connect_one(node: Node) -> void:
	if (
		node
		and is_instance_valid(node)
		and not node.child_order_changed.is_connected(_on_board_changed)
	):
		node.child_order_changed.connect(_on_board_changed)


func _disconnect_one(node: Node) -> void:
	if (
		node
		and is_instance_valid(node)
		and node.child_order_changed.is_connected(_on_board_changed)
	):
		node.child_order_changed.disconnect(_on_board_changed)


func _on_board_changed() -> void:
	if not Engine.is_editor_hint() and auto_play and active_group != ActiveGroup.NONE:
		_pre_hide_board()
	if _play_scheduled:
		return
	_play_scheduled = true
	call_deferred("_deferred_try_play")


func _deferred_try_play() -> void:
	_play_scheduled = false
	if _count_cells() > 0:
		play()


func _count_cells() -> int:
	if not board_view or not is_instance_valid(board_view):
		return 0
	var result: Array = []
	_collect_cells_recursive(board_view, result)
	return result.size()


func _build_cells() -> void:
	_cells.clear()
	_rings.clear()
	if not board_view or not is_instance_valid(board_view):
		return
	var cell_list: Array = []
	_collect_cells_recursive(board_view, cell_list)
	var count := cell_list.size()
	if count == 0:
		return
	var n := int(round(sqrt(float(count))))
	if n * n != count:
		push_warning("BoardCellIntro: 格子数 %d 不是完全平方数。" % count)
		return
	for i in count:
		_cells.append(cell_list[i] as CanvasItem)

	match active_group:
		ActiveGroup.GROUP_2:
			for i in count:
				_rings.append(i / n)
		ActiveGroup.GROUP_3:
			for i in count:
				var r: int = i / n
				var c: int = i % n
				_rings.append(c + (n - 1 - r))
		ActiveGroup.GROUP_4:
			var cell_colors: Array = []
			for cell in _cells:
				if cell is CellView:
					cell_colors.append((cell as CellView)._region_color)
				else:
					cell_colors.append(Color.WHITE)

			var unique_colors: Array = []
			for col: Color in cell_colors:
				var found := false
				for uc: Color in unique_colors:
					if col.is_equal_approx(uc):
						found = true
						break
				if not found:
					unique_colors.append(col)
			unique_colors.sort_custom(
				func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance()
			)

			for i in count:
				var col: Color = cell_colors[i]
				var idx := 0
				for j in unique_colors.size():
					if col.is_equal_approx(unique_colors[j]):
						idx = j
						break
				_rings.append(idx)
		_:
			var cx: float = (n - 1) * 0.5
			var cy: float = (n - 1) * 0.5
			for i in count:
				var r: int = i / n
				var c: int = i % n
				_rings.append(int(maxf(absf(float(r) - cx), absf(float(c) - cy))))

	_randoms.clear()
	var _use_random := active_group == ActiveGroup.GROUP_4 and g4_random_delay > 0.0
	for _ri in count:
		_randoms.append(randf() * g4_random_delay if _use_random else 0.0)


func _collect_cells_recursive(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child is CellView:
			result.append(child)
		else:
			_collect_cells_recursive(child, result)


func _pre_hide_board() -> void:
	if not (board_view and is_instance_valid(board_view)):
		return

	if board_view is CanvasItem:
		_set_alpha(board_view as CanvasItem, 0.0)
	var cells: Array = []
	_collect_cells_recursive(board_view, cells)
	for cell in cells:
		if is_instance_valid(cell):
			_set_alpha(cell as CanvasItem, 0.0)


func _get_param_hash() -> int:
	if active_group == ActiveGroup.NONE:
		return hash([0])
	var p := _params()
	return hash(
		[
			int(active_group),
			p.ld,
			p.ri,
			p.cfd,
			int(p.fe),
			g4_random_delay,
			p.cse,
			p.csd,
			p.csf,
			int(p.csc),
			p.cfe,
			p.cfdu,
			int(p.cfea),
			p.se,
			p.sd,
			p.sf,
			int(p.sc),
			p.te,
			p.td,
			p.tox,
			p.toy,
			int(p.tcx),
			int(p.tcy)
		]
	)


func _set_alpha(node: CanvasItem, alpha: float) -> void:
	var col := node.modulate
	col.a = alpha
	node.modulate = col


func _set_scale(node: Node, scl: Vector2) -> void:
	if node is Node2D:
		(node as Node2D).scale = scl
	elif node is Control:
		(node as Control).scale = scl


func _center_pivot(node: Node) -> void:
	if node is Control:
		var c := node as Control
		c.pivot_offset = c.size / 2.0


func _get_position(node: Node) -> Vector2:
	if node is Node2D:
		return (node as Node2D).position
	elif node is Control:
		return (node as Control).position
	return Vector2.ZERO


func _set_position(node: Node, pos: Vector2) -> void:
	if node is Node2D:
		(node as Node2D).position = pos
	elif node is Control:
		(node as Control).position = pos


func _ease_t(t: float, ease_type: AutoAnimCurve.EaseType, custom_curve: Curve) -> float:
	if ease_type == AutoAnimCurve.EaseType.CUSTOM and custom_curve != null:
		return custom_curve.sample(t)
	if ease_type == AutoAnimCurve.EaseType.LINEAR:
		return t
	return Tween.interpolate_value(0.0, 1.0, t, 1.0, _get_trans(ease_type), _get_ease(ease_type))


func _get_trans(ease_type: AutoAnimCurve.EaseType) -> Tween.TransitionType:
	match ease_type:
		AutoAnimCurve.EaseType.SINE_IN, AutoAnimCurve.EaseType.SINE_OUT, AutoAnimCurve.EaseType.SINE_IN_OUT:
			return Tween.TRANS_SINE
		AutoAnimCurve.EaseType.QUAD_IN, AutoAnimCurve.EaseType.QUAD_OUT, AutoAnimCurve.EaseType.QUAD_IN_OUT:
			return Tween.TRANS_QUAD
		AutoAnimCurve.EaseType.CUBIC_IN, AutoAnimCurve.EaseType.CUBIC_OUT, AutoAnimCurve.EaseType.CUBIC_IN_OUT:
			return Tween.TRANS_CUBIC
		AutoAnimCurve.EaseType.QUART_IN, AutoAnimCurve.EaseType.QUART_OUT, AutoAnimCurve.EaseType.QUART_IN_OUT:
			return Tween.TRANS_QUART
		AutoAnimCurve.EaseType.QUINT_IN, AutoAnimCurve.EaseType.QUINT_OUT, AutoAnimCurve.EaseType.QUINT_IN_OUT:
			return Tween.TRANS_QUINT
		AutoAnimCurve.EaseType.EXPO_IN, AutoAnimCurve.EaseType.EXPO_OUT, AutoAnimCurve.EaseType.EXPO_IN_OUT:
			return Tween.TRANS_EXPO
		AutoAnimCurve.EaseType.CIRC_IN, AutoAnimCurve.EaseType.CIRC_OUT, AutoAnimCurve.EaseType.CIRC_IN_OUT:
			return Tween.TRANS_CIRC
		AutoAnimCurve.EaseType.BACK_IN, AutoAnimCurve.EaseType.BACK_OUT, AutoAnimCurve.EaseType.BACK_IN_OUT:
			return Tween.TRANS_BACK
		AutoAnimCurve.EaseType.ELASTIC_IN, AutoAnimCurve.EaseType.ELASTIC_OUT, AutoAnimCurve.EaseType.ELASTIC_IN_OUT:
			return Tween.TRANS_ELASTIC
		AutoAnimCurve.EaseType.BOUNCE_IN, AutoAnimCurve.EaseType.BOUNCE_OUT, AutoAnimCurve.EaseType.BOUNCE_IN_OUT:
			return Tween.TRANS_BOUNCE
	return Tween.TRANS_LINEAR


func _get_ease(ease_type: AutoAnimCurve.EaseType) -> Tween.EaseType:
	var offset := (ease_type - AutoAnimCurve.EaseType.SINE_IN) % 3
	match offset:
		1:
			return Tween.EASE_OUT
		2:
			return Tween.EASE_IN_OUT
		_:
			return Tween.EASE_IN
