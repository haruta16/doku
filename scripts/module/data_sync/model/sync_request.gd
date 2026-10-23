## 待执行同步请求的值对象；reason 用于定位触发来源，force 表示需要强制推进同步。

class_name SyncRequest
extends RefCounted

var reason: String = ""

var force: String = ""


static func of(sync_reason: String, sync_force: String) -> SyncRequest:
	var request := SyncRequest.new()
	request.reason = sync_reason
	request.force = sync_force
	return request
