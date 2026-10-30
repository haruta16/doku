## 下载并合并阶段的返回值；记录是否首次上传、当前版本与令牌，让上传阶段接续处理。

class_name DownloadMergeResult
extends RefCounted

var ok: bool = false

var reason: String = ""

var first_upload: bool = false

var sync_code: int = 0

var bearer: String = ""


static func fail(fail_reason: String, current_bearer: String = "") -> DownloadMergeResult:
	var result := DownloadMergeResult.new()
	result.reason = fail_reason
	result.bearer = current_bearer
	return result


static func first_time(current_bearer: String) -> DownloadMergeResult:
	var result := DownloadMergeResult.new()
	result.ok = true
	result.first_upload = true
	result.bearer = current_bearer
	return result


static func merged(cloud_sync_code: int, current_bearer: String) -> DownloadMergeResult:
	var result := DownloadMergeResult.new()
	result.ok = true
	result.sync_code = cloud_sync_code
	result.bearer = current_bearer
	return result
