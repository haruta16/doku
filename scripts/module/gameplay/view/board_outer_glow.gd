## 跟随棋盘背景几何的外发光控件，可把顶部标签一并纳入轮廓；布局变化通过信号驱动同步。
@tool
class_name BoardOuterGlow
extends ColorRect

const PREVIEW_BOARD_SIZE: Vector2 = Vector2(1008.0, 1008.0)
const DEFAULT_PROFILE_SPAN_PX: float = 64.0
const BOARD_VIEW_PATH: NodePath = NodePath("../BoardView")

const _TAB_SHADER: Shader = preload("res://assets/effect/shader/board_outer_glow_tab.gdshader")

@export_group("Profile")
@export var glow_profile: Texture2D:
	set(value):
		glow_profile = value
		_apply_profile()
		_queue_geometry_sync()

var _shader_material: ShaderMaterial = null

var _base_shader: Shader = null
var _board_view: BoardView = null

var _initial_color: Color = Color(1, 1, 1, 1)

var _tab: Control = null

var _tab_side_inset: float = 0.0

var _tab_corner_radius: float = 0.0

var _tab_fillet_radius: float = 0.0

var _tab_fillet_baseline_y: float = 0.0


## 保存原始外观，连接棋盘几何信号并同步初始发光范围。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_initial_color = color
	_shader_material = material as ShaderMaterial
	if _shader_material == null:
		push_error("BoardOuterGlow: ShaderMaterial 未配置。")
		return
	_base_shader = _shader_material.shader
	_apply_profile()
	_board_view = get_node_or_null(BOARD_VIEW_PATH) as BoardView
	if _board_view == null:
		if not Engine.is_editor_hint():
			push_error("BoardOuterGlow: 同级 BoardView 不存在。")
	else:
		_connect_board_view()
	_sync_geometry()


## 退出场景时断开棋盘与顶部标签的信号连接。
func _exit_tree() -> void:
	_disconnect_board_view()
	_disconnect_tab()


## 设置参与发光轮廓的顶部标签；标签必须与棋盘同父级，参数变化后延迟同步几何。
func set_top_tab(
	tab: Control,
	side_inset_px: float = 0.0,
	corner_radius_px: float = 0.0,
	fillet_radius_px: float = 0.0,
	fillet_baseline_px: float = 0.0
) -> void:
	if tab != null and _board_view != null and tab.get_parent() != _board_view.get_parent():
		push_warning("BoardOuterGlow: 凸舌节点必须与 BoardView 同父，已忽略：%s" % tab.get_path())
		tab = null
	if _tab != tab:
		_disconnect_tab()
		_tab = tab
		_connect_tab()
	_tab_side_inset = side_inset_px
	_tab_corner_radius = corner_radius_px
	_tab_fillet_radius = fillet_radius_px
	_tab_fillet_baseline_y = fillet_baseline_px
	_queue_geometry_sync()


## 替换发光 RGB，同时保留当前透明度。
func set_glow_color(new_color: Color) -> void:
	color = Color(new_color.r, new_color.g, new_color.b, color.a)


## 恢复初始发光 RGB，同时保留当前透明度。
func reset_glow_color() -> void:
	color = Color(_initial_color.r, _initial_color.g, _initial_color.b, color.a)


## 立即按棋盘与顶部标签现状同步发光布局。
func sync_to_board() -> void:
	_sync_geometry()


## 监听棋盘控件尺寸和背景矩形变化。
func _connect_board_view() -> void:
	if _board_view == null or not is_instance_valid(_board_view):
		return
	if not _board_view.item_rect_changed.is_connected(_on_board_rect_changed):
		_board_view.item_rect_changed.connect(_on_board_rect_changed)
	if not _board_view.background_rect_changed.is_connected(_on_board_rect_changed):
		_board_view.background_rect_changed.connect(_on_board_rect_changed)


## 断开棋盘几何监听，避免持有失效节点。
func _disconnect_board_view() -> void:
	if _board_view == null or not is_instance_valid(_board_view):
		return
	if _board_view.item_rect_changed.is_connected(_on_board_rect_changed):
		_board_view.item_rect_changed.disconnect(_on_board_rect_changed)
	if _board_view.background_rect_changed.is_connected(_on_board_rect_changed):
		_board_view.background_rect_changed.disconnect(_on_board_rect_changed)


## 棋盘几何变化后安排一次延迟同步。
func _on_board_rect_changed() -> void:
	_queue_geometry_sync()


## 监听顶部标签的尺寸与可见性变化。
func _connect_tab() -> void:
	if _tab == null or not is_instance_valid(_tab):
		return
	if not _tab.item_rect_changed.is_connected(_on_tab_changed):
		_tab.item_rect_changed.connect(_on_tab_changed)
	if not _tab.visibility_changed.is_connected(_on_tab_changed):
		_tab.visibility_changed.connect(_on_tab_changed)


## 移除顶部标签监听。
func _disconnect_tab() -> void:
	if _tab == null or not is_instance_valid(_tab):
		return
	if _tab.item_rect_changed.is_connected(_on_tab_changed):
		_tab.item_rect_changed.disconnect(_on_tab_changed)
	if _tab.visibility_changed.is_connected(_on_tab_changed):
		_tab.visibility_changed.disconnect(_on_tab_changed)


## 标签布局或可见性变化后安排同步。
func _on_tab_changed() -> void:
	_queue_geometry_sync()


## 节点仍在树中时延迟同步，让当前布局修改先完成。
func _queue_geometry_sync() -> void:
	if is_inside_tree():
		_sync_geometry.call_deferred()


## 把棋盘背景和可见标签合成发光矩形，选择对应着色器并更新尺寸、圆角等参数。
func _sync_geometry() -> void:
	if _shader_material == null:
		return
	var visible_size: Vector2 = PREVIEW_BOARD_SIZE
	var board_origin: Vector2 = Vector2.ZERO
	var corner_radius: float = float(BoardView.BOARD_BG_CORNER_RADIUS)
	var has_board: bool = _board_view != null and is_instance_valid(_board_view)
	if has_board:
		var board_scale: Vector2 = _board_view.scale.abs()
		var background_rect: Rect2 = _board_view.get_board_background_rect_local()
		visible_size = Vector2(
			background_rect.size.x * board_scale.x, background_rect.size.y * board_scale.y
		)
		board_origin = (
			_board_view.position
			+ Vector2(
				background_rect.position.x * board_scale.x,
				background_rect.position.y * board_scale.y
			)
		)
		corner_radius = _board_view.get_board_background_corner_radius_px()
	if visible_size.x <= 0.0 or visible_size.y <= 0.0:
		return
	var span: float = _profile_span_px()

	var tab_rect: Rect2 = Rect2()
	if has_board and _tab != null and is_instance_valid(_tab) and _tab.visible:
		tab_rect = Rect2(_tab.position, _tab.size)
	var layout: Dictionary = compute_tab_layout(
		Rect2(board_origin, visible_size),
		tab_rect,
		span,
		_tab_side_inset,
		_tab_corner_radius,
		_tab_fillet_radius,
		_tab_fillet_baseline_y
	)
	var has_tab: bool = bool(layout["has_tab"])
	var panel_size: Vector2
	if has_tab:
		var panel_rect: Rect2 = layout["panel_rect"]
		position = panel_rect.position
		panel_size = panel_rect.size
	else:
		panel_size = visible_size + Vector2.ONE * span * 2.0
		position = board_origin - Vector2.ONE * span if has_board else Vector2.ZERO
	size = panel_size
	pivot_offset = Vector2.ZERO

	var wanted_shader: Shader = _TAB_SHADER if has_tab else _base_shader
	if wanted_shader != null and _shader_material.shader != wanted_shader:
		_shader_material.shader = wanted_shader
		_apply_profile()
	_shader_material.set_shader_parameter("panel_size_px", panel_size)
	_shader_material.set_shader_parameter("board_size_px", visible_size)
	_shader_material.set_shader_parameter("corner_radius_px", corner_radius)
	_shader_material.set_shader_parameter("profile_span_px", span)
	if has_tab:
		_shader_material.set_shader_parameter("board_center_shift_px", layout["center_shift"])
		var tab_px: Rect2 = layout["tab_rect_px"]
		_shader_material.set_shader_parameter(
			"tab_rect_px",
			Vector4(tab_px.position.x, tab_px.position.y, tab_px.size.x, tab_px.size.y)
		)
		_shader_material.set_shader_parameter("tab_corner_radius_px", _tab_corner_radius)
		_shader_material.set_shader_parameter("tab_fillet_radius_px", _tab_fillet_radius)
		_shader_material.set_shader_parameter("tab_flare_baseline_px", layout["flare_baseline_px"])


## 根据棋盘与标签矩形计算合并轮廓、偏移及发光基线，返回几何参数字典。
static func compute_tab_layout(
	board_rect: Rect2,
	tab_rect: Rect2,
	span: float,
	side_inset: float,
	corner_radius: float,
	fillet_radius: float,
	fillet_baseline: float
) -> Dictionary:
	var has_tab: bool = tab_rect.size.x > 0.0 and tab_rect.size.y > 0.0
	if not has_tab:
		return {
			"has_tab": false,
			"panel_rect": Rect2(),
			"center_shift": Vector2.ZERO,
			"tab_rect_px": Rect2(),
			"flare_baseline_px": 0.0,
		}
	var panel_rect: Rect2 = board_rect.merge(tab_rect).grow(span)
	var center_shift: Vector2 = (
		(board_rect.get_center() - panel_rect.position) - panel_rect.size * 0.5
	)
	var baseline_y: float = tab_rect.position.y + fillet_baseline
	var white_left: float = tab_rect.position.x + side_inset
	var white_right: float = tab_rect.end.x - side_inset
	var white_top: float = tab_rect.position.y
	var white_bottom: float = baseline_y + corner_radius + fillet_radius
	var tab_px: Rect2 = Rect2(
		Vector2(white_left, white_top) - panel_rect.position,
		Vector2(white_right - white_left, white_bottom - white_top)
	)
	return {
		"has_tab": true,
		"panel_rect": panel_rect,
		"center_shift": center_shift,
		"tab_rect_px": tab_px,
		"flare_baseline_px": baseline_y - panel_rect.position.y,
	}


## 将发光剖面纹理传给材质。
func _apply_profile() -> void:
	if _shader_material != null:
		_shader_material.set_shader_parameter("glow_profile", glow_profile)


## 用剖面纹理高度决定发光扩展范围，无纹理时使用默认宽度。
func _profile_span_px() -> float:
	if glow_profile != null:
		return maxf(float(glow_profile.get_height()), 1.0)
	return DEFAULT_PROFILE_SPAN_PX
