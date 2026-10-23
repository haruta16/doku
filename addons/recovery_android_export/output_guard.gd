## 记录导出前产物指纹；清理失败导出时不能把未被本次导出改动的旧 APK 当作垃圾删除。
@tool
extends RefCounted


static func snapshot(path: String) -> Dictionary:
	var existed := FileAccess.file_exists(path)
	var digest := FileAccess.get_sha256(path) if existed else ""
	return {"ok": not existed or not digest.is_empty(), "existed": existed, "sha256": digest}


static func remove_changed_output(path: String, before: Dictionary) -> Dictionary:
	if not bool(before.get("ok", false)):
		return {"ok": false, "error": "original output fingerprint unavailable; output retained"}
	if not FileAccess.file_exists(path):
		return {"ok": true, "removed": false, "reason": "no output"}
	var current := FileAccess.get_sha256(path)
	if current.is_empty():
		return {"ok": false, "error": "current output fingerprint unavailable; output retained"}
	if bool(before.existed) and current == str(before.sha256):
		return {"ok": true, "removed": false, "reason": "previous output unchanged"}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		return {"ok": false, "error": "cannot remove changed output (error %d): %s" % [error, path]}
	return {"ok": true, "removed": true, "reason": "output created or changed during this export"}
