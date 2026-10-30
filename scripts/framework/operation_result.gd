## 操作结果仍是普通 Dictionary：ok 判断成败，error 是稳定机器码，detail 只用于诊断。
## status 属于各业务的状态（如 loaded、already_applied、active），不能代替 ok。
## 存储/库存失败保留旧 status 字段供兼容；新的失败分支统一读取 error。
class_name OperationResult
extends RefCounted


static func success(fields: Dictionary = {}) -> Dictionary:
	var result := fields.duplicate()
	result["ok"] = true
	result["error"] = ""
	return result


static func failure(error_code: String, explanation: String = "", fields: Dictionary = {}) -> Dictionary:
	var result := fields.duplicate()
	result["ok"] = false
	result["error"] = error_code
	result["detail"] = explanation
	return result


## 上层保留自己的失败语义，同时留下原始原因；不会把机器码替换成说明文字。
static func wrap_failure(error_code: String, cause: Dictionary, explanation: String = "") -> Dictionary:
	return failure(error_code, explanation if not explanation.is_empty() else detail(cause), {"cause": cause.duplicate(true)})


static func code(result: Dictionary) -> String:
	return str(result.get("error", ""))


static func detail(result: Dictionary) -> String:
	return str(result.get("detail", ""))


## 日志入口。页面应按 error 选择本地化提示，不直接向玩家展示诊断内容。
static func describe(result: Dictionary) -> String:
	var description := code(result)
	var explanation := detail(result)
	if not explanation.is_empty():
		description += ": " + explanation
	var cause: Variant = result.get("cause")
	if cause is Dictionary and not code(cause).is_empty():
		description += " [cause: " + code(cause) + "]"
	return description
