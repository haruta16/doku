## 用户价值查询：向原生 SDK 请求 LTV，结果通过信号异步返回。
class_name UniKitGrtModule
extends UniKitModuleBase

signal ltv_received(ltv: float)


## 发起原生 LTV 查询，调用方应监听 ltv_received 获取结果。
func get_ltv() -> void:
	if _host._plugin == null:
		return
	_host._plugin.getLTV()
