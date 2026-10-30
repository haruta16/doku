## 一次同步的统一返回值；将完成状态、数据变化、版本信息与失败原因交给调用者。

class_name SyncResult
extends RefCounted

var ok: bool = false

var reason: String = ""

var changed: bool = false

var sync_code: int = 0

var is_first_upload: bool = false


static func fail(fail_reason: String) -> SyncResult:
	var result := SyncResult.new()
	result.reason = fail_reason
	return result


static func success(final_sync_code: int, has_merged: bool, built_new: bool) -> SyncResult:
	var result := SyncResult.new()
	result.ok = true
	result.sync_code = final_sync_code
	result.changed = has_merged
	result.is_first_upload = built_new
	return result
