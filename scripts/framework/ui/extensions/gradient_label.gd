## 渐变文字控件：把颜色、方向和控件尺寸同步给文字材质。
class_name GradientLabel
extends Label

@export var start_color: Color = Color.WHITE: # 起点 RGB；配套普通文字 shader 的输出透明度沿用原生字形管线
	set(value):
		start_color = value
		_sync_colors()

@export var end_color: Color = Color(0.55, 0.55, 0.55, 1.0): # 终点 RGB；本 shader 不用两端颜色 alpha 做渐隐
	set(value):
		end_color = value
		_sync_colors()

@export var direction: Vector2 = Vector2(0.0, 1.0): # 非负方向分量：(0,1) 上到下，(1,0) 左到右；反向渐变交换两端色
	set(value):
		direction = value
		_sync_direction()

const _GRADIENT_SHADER: Shader = preload("res://scripts/framework/ui/shaders/gradient_text.gdshader")

var _material: ShaderMaterial = null # 此实例独占的材质；shader 资源可共享，uniform 值不可互相覆盖


## 为当前标签单独创建材质，避免修改共享材质影响其他标签；尺寸变化时只更新矩形参数。
func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _GRADIENT_SHADER
	material = _material
	resized.connect(_sync_rect_size)
	_sync_all()


## 材质就绪后一次同步颜色、方向和尺寸，接上进树前 Inspector 已设置的值。
func _sync_all() -> void:
	_sync_colors()
	_sync_direction()
	_sync_rect_size()


## 把渐变两端颜色写入本标签材质；尚未创建材质时先保留属性，等 _ready 统一同步。
func _sync_colors() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("start_color", start_color)
	_material.set_shader_parameter("end_color", end_color)


## 同步局部矩形内的渐变方向；脚本不做归一化，由配套 shader 处理分量和。
func _sync_direction() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("direction", direction)


## 同步节点的局部宽高；移动或父级动画不改变局部渐变范围，无需每帧发送全局矩形。
func _sync_rect_size() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("rect_size", size)
