## 渐变文字控件：把颜色、方向和控件尺寸同步给文字材质。
class_name GradientLabel
extends Label

@export var start_color: Color = Color.WHITE:
	set(value):
		start_color = value
		_sync_colors()

@export var end_color: Color = Color(0.55, 0.55, 0.55, 1.0):
	set(value):
		end_color = value
		_sync_colors()

@export var direction: Vector2 = Vector2(0.0, 1.0):
	set(value):
		direction = value
		_sync_direction()

const _GRADIENT_SHADER: Shader = preload("res://assets/shaders/gradient_text.gdshader")

var _material: ShaderMaterial = null


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _GRADIENT_SHADER
	material = _material
	resized.connect(_sync_rect_size)
	_sync_all()


func _sync_all() -> void:
	_sync_colors()
	_sync_direction()
	_sync_rect_size()


func _sync_colors() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("start_color", start_color)
	_material.set_shader_parameter("end_color", end_color)


func _sync_direction() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("direction", direction)


func _sync_rect_size() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("rect_size", size)
