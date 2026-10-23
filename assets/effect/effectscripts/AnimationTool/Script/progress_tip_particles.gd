@tool
class_name ProgressTipParticles
extends CPUParticles2D

const EPS := 0.0001

@export_group("跟随目标")

@export var ring_path: NodePath = ^"../ProgressbarA"

@export_group("环几何")

@export var center: Vector2 = Vector2(370.0, 370.0)

@export var radius: float = 229.6

@export_range(-360.0, 360.0) var start_deg: float = 0.0

@export var clockwise: bool = true

var _ring: CanvasItem


func _ready() -> void:
	_ring = get_node_or_null(ring_path) as CanvasItem


func _process(_delta: float) -> void:
	if _ring == null:
		_ring = get_node_or_null(ring_path) as CanvasItem
		if _ring == null:
			return
	var mat := _ring.material as ShaderMaterial
	if mat == null:
		return
	var progress: float = mat.get_shader_parameter("progress")

	emitting = progress > EPS

	var ang_deg: float = start_deg + (progress * 360.0 if clockwise else -progress * 360.0)
	var a: float = deg_to_rad(ang_deg)

	position = center + Vector2(sin(a), -cos(a)) * radius
