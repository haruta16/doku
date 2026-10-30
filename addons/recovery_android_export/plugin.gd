## 本地恢复适配：使用 Godot 4.6 官方预编译清单扩展点保留原包的 Android 目标版本。
@tool
extends EditorPlugin

const EXPORTER = preload("res://addons/recovery_android_export/export_plugin.gd")
var _exporter: EditorExportPlugin


func _enter_tree() -> void:
	_exporter = EXPORTER.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
