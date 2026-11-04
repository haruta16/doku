## 发布校验的三个明确入口；回调均无副作用并返回含 bool ok 的 Dictionary。
## 包装逐文件回调不会改变目录/媒体合同；不反射 Callable 所属对象。
class_name ContentValidation
extends RefCounted

var _file_check: Callable # 逐文件业务检查：接收 logical_id、已解析数据；不代替外层签名/哈希校验。
var _catalog_check: Callable # 跨文件检查：接收完整 Catalog，核对产品需要的来源组合与引用。
var _media_check: Callable # 挂载后的媒体合同检查：接收 Catalog，核对实际资源能否被产品使用。


## 分别注入三个校验阶段；未提供某阶段时只跳过该产品检查，不省略内容层的通用验证。
func _init(file_check: Callable = Callable(), catalog_check: Callable = Callable(), media_check: Callable = Callable()) -> void:
	_file_check = file_check
	_catalog_check = catalog_check
	_media_check = media_check


## 执行单个 JSON 的产品校验，返回原业务回执或不合法回执的统一错误。
func check_file(logical_id: String, value: Variant) -> Dictionary:
	return _run(_file_check, [logical_id, value], "file_validator_result")


## 执行整目录产品校验，用于跨文件依赖或整体配置一致性。
func check_catalog(catalog: RefCounted) -> Dictionary:
	return _run(_catalog_check, [catalog], "catalog_validator_result")


## 执行媒体已可加载后的产品校验；不能用文件哈希正确替代资源消费合同。
func check_media(catalog: RefCounted) -> Dictionary:
	return _run(_media_check, [catalog], "media_validator_result")


## 空回调视为无附加限制；失效回调或缺少布尔 ok 的返回值都失败，防止误把异常接入当通过。
func _run(callback: Callable, arguments: Array, error: String) -> Dictionary:
	if callback.is_null():
		return {"ok": true, "error": ""}
	if not callback.is_valid():
		return {"ok": false, "error": error, "detail": "validator callback is no longer valid"}
	var result: Variant = callback.callv(arguments)
	if not result is Dictionary or not result.get("ok") is bool:
		return {"ok": false, "error": error, "detail": "validator must return Dictionary with bool ok"}
	return result
