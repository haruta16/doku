## UniKit 子模块基类：保存宿主节点，供模块访问同一个原生插件。
class_name UniKitModuleBase
extends RefCounted

var _host: Node = null


## 保存 UniKit 宿主引用，子模块通过它共用原生桥接对象。
func _init(host: Node) -> void:
	_host = host
