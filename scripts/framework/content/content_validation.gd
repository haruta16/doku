## 发布校验的三个明确入口；回调均无副作用并返回含 bool ok 的 Dictionary。
## 包装逐文件回调不会改变目录/媒体合同；不反射 Callable 所属对象。
class_name ContentValidation
extends RefCounted

var _file_check: Callable
var _catalog_check: Callable
var _media_check: Callable


func _init(file_check: Callable = Callable(), catalog_check: Callable = Callable(), media_check: Callable = Callable()) -> void:
	_file_check = file_check
	_catalog_check = catalog_check
	_media_check = media_check


func check_file(logical_id: String, value: Variant) -> Dictionary:
	return _run(_file_check, [logical_id, value], "file_validator_result")


func check_catalog(catalog: RefCounted) -> Dictionary:
	return _run(_catalog_check, [catalog], "catalog_validator_result")


func check_media(catalog: RefCounted) -> Dictionary:
	return _run(_media_check, [catalog], "media_validator_result")


func _run(callback: Callable, arguments: Array, error: String) -> Dictionary:
	if callback.is_null():
		return {"ok": true, "error": ""}
	if not callback.is_valid():
		return {"ok": false, "error": error, "detail": "validator callback is no longer valid"}
	var result: Variant = callback.callv(arguments)
	if not result is Dictionary or not result.get("ok") is bool:
		return {"ok": false, "error": error, "detail": "validator must return Dictionary with bool ok"}
	return result
