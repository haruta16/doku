## 云端存档解析结果；明确区分请求失败、云端尚无存档，以及已取得有效数据三种情况。

class_name CloudSaveResult
extends RefCounted

var ok: bool = false

var has_cloud_data: bool = false

var root: Dictionary = {}

var sync_code: int = -1

var reason: String = ""


static func fail(fail_reason: String) -> CloudSaveResult:
	var result := CloudSaveResult.new()
	result.reason = fail_reason
	return result


static func empty(cloud_sync_code: int = -1) -> CloudSaveResult:
	var result := CloudSaveResult.new()
	result.ok = true
	result.sync_code = cloud_sync_code
	return result


static func loaded(remote_root: Dictionary, cloud_sync_code: int) -> CloudSaveResult:
	var result := CloudSaveResult.new()
	result.ok = true
	result.has_cloud_data = true
	result.root = remote_root
	result.sync_code = cloud_sync_code
	return result
