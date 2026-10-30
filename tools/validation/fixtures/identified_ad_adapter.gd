## 仅用于隔离测试：经过真实原生桥分支，不启动单例初始化。
extends "res://products/meowdoku/app/platform/unikit_manager.gd"


func _ready() -> void:
	pass


func _is_ad_mock_enabled() -> bool:
	return false
