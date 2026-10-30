## 圆形图标按钮：初始化点击反馈并转发按钮事件。
@tool
class_name RoundIconBtn
extends Button

@export var icon_texture: Texture2D:
	set(value):
		icon_texture = value
		if is_node_ready():
			_icon.texture = value

@onready var _icon: TextureRect = $Icon


func _ready() -> void:
	if icon_texture != null:
		_icon.texture = icon_texture
