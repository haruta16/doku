## 单任务内容交付器：发现、有限重试、进度、取消；成功安装之后由调用方登记 pending。
## 请求取消不会发布半包；临时目录在成功、错误或取消返回前清理。
class_name ContentDownloader
extends Node

const Validation = preload("res://scripts/framework/content/content_validation.gd")

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const Channel = preload("res://scripts/framework/content/content_channel.gd")
const Store = preload("res://scripts/framework/content/content_store.gd")

## 进度同步通知：phase 区分发现/下载/安装/结束，监听者可以请求取消，不能把下载完成当作已激活。
signal progress_changed(progress: Dictionary)

var max_attempts: int = 3 # 每个 HTTP 文件请求的尝试次数；执行时限制到 1～5 次。
var timeout_seconds: float = 20.0 # 每次 HTTP 请求超时秒数；执行时限制到 0.1～120 秒。
var retry_delay_seconds: float = 0.25 # 有限指数退避的起始秒数；每轮等待仍允许取消。
var _busy := false # 单任务占位；发现频道、下载、安装和最终清理属于同一次任务。
var _cancelled := false # 当前任务取消标记；HTTP 取消后仍由外层流程统一清理临时目录。
var _request: HTTPRequest # 当前活跃 HTTPRequest 子节点；cancel 可终止它，不直接发布结果。
var _progress: Dictionary = {} # 最近一次进度快照；向监听者发布副本，避免外部改写任务统计。
var _release: String = "" # 验签清单中的发布身份；清单尚未验证时为空。
var _completed_bytes: int = 0 # 已经下载并核对哈希的载荷字节数，不包含当前未完成文件。
var _total_bytes: int = 0 # 清单声明的载荷总字节数；不把频道和清单元数据计入。


## 查询是否仍有交付任务占位；取消请求发出后，直到 _finish 清理完才变为 false。
func is_busy() -> bool:
	return _busy


## 返回最近进度的深拷贝，供 UI 查询而不暴露内部可变字典。
func progress_snapshot() -> Dictionary:
	return _progress.duplicate(true)


## 标记任务取消并终止当前 HTTP 请求；后续等待检查标记退出，统一结束入口负责清理目录。
func cancel() -> void:
	if not _busy:
		return
	_cancelled = true
	if is_instance_valid(_request):
		_request.cancel_request()


## 节点离树即请求取消；不会把未完成下载登记成 pending 或切换活动内容。
func _exit_tree() -> void:
	cancel()


## 显式指定版本时可省略身份；此时调用者和 HTTPS 源负责选择版本的新鲜度。
## 自动固定地址更新应同时绑定 release 与签名清单原始字节哈希。
func download_release(store: RefCounted, release_url: String, staging_root: String, validator: Validation = null, allow_local_http: bool = false, expected_release: String = "", expected_manifest_sha256: String = "") -> Dictionary:
	var identity := release_identity(expected_release, expected_manifest_sha256)
	if not identity.ok:
		return identity
	var opened := _begin(release_url, staging_root, allow_local_http)
	if not opened.ok:
		return opened
	var result := await _download_into(store, release_url.trim_suffix("/"), opened.work, validator, identity.value, "release_identity_mismatch")
	return _finish(opened.work, result)


## 要求 release 与清单 SHA 成对提供；都为空可表示由调用方自行选择版本，required=true 时禁止省略。
static func release_identity(release: String, manifest_sha256: String, required: bool = false) -> Dictionary:
	if release.is_empty() and manifest_sha256.is_empty():
		return Manifest.failure("release_identity_required") if required else {"ok": true, "value": {}}
	if not Manifest.identifier(release) or not Manifest.is_sha256(manifest_sha256):
		return Manifest.failure("release_identity_invalid")
	return {"ok": true, "value": {"release": release, "manifest_sha256": manifest_sha256}}


## 频道和其发布在同一取消范围内；拿到不兼容、旧版或已拒绝目标不会改动活动版本。
func download_from_channel(store: RefCounted, channel_url: String, channel: String, staging_root: String, validator: Validation = null, allow_local_http: bool = false) -> Dictionary:
	var opened := _begin(channel_url, staging_root, allow_local_http)
	if not opened.ok:
		return opened
	var result := await _discover_and_download(store, channel_url.trim_suffix("/"), channel, opened.work, validator, allow_local_http)
	return _finish(opened.work, result)


## 验证节点、单任务状态和 URL 后创建随机暂存目录，再清空本次统计并占位。
func _begin(url: String, staging_root: String, allow_local_http: bool) -> Dictionary:
	if _busy:
		return Manifest.failure("download_busy")
	if not is_inside_tree():
		return Manifest.failure("downloader_not_in_tree")
	if not _allowed_url(url, allow_local_http):
		return Manifest.failure("download_url")
	var work := staging_root.path_join("download_" + Crypto.new().generate_random_bytes(12).hex_encode())
	if DirAccess.make_dir_recursive_absolute(work) != OK:
		return Manifest.failure("download_directory")
	_busy = true
	_cancelled = false
	_release = ""
	_completed_bytes = 0
	_total_bytes = 0
	_emit_progress("starting")
	return {"ok": true, "work": work}


## 递归清理本次暂存目录、释放忙状态并发布最终进度；安装成功仍由调用方另行 stage。
func _finish(work: String, result: Dictionary) -> Dictionary:
	Store._remove_tree(work)
	_busy = false
	_request = null
	_emit_progress("complete" if result.ok else ("cancelled" if result.get("cancelled", false) else "failed"))
	return result


## 下载并验证频道及签名，先持久化选择水位，再下载其绑定 release/清单哈希的发布。
func _discover_and_download(store: RefCounted, base_url: String, channel: String, work: String, validator: Validation, allow_local_http: bool) -> Dictionary:
	for metadata: Dictionary in [{"name": "channel.json", "limit": Channel.MAX_BYTES}, {"name": "channel.sig", "limit": 1024}]:
		var fetched := await _fetch(base_url + "/" + metadata.name, work.path_join(metadata.name), metadata.limit, "discovering")
		if not fetched.ok:
			return fetched
	if _cancelled:
		return _cancel_result()
	var selected: Dictionary = store.accept_channel(FileAccess.get_file_as_bytes(work.path_join("channel.json")), FileAccess.get_file_as_bytes(work.path_join("channel.sig")), channel, allow_local_http)
	if not selected.ok:
		return selected
	if store.state_snapshot().rejected == selected.value.release:
		return Manifest.failure("release_rejected")
	var result := await _download_into(store, selected.value.url.trim_suffix("/"), work, validator, selected.value)
	result["channel"] = channel
	result["channel_revision"] = selected.revision
	return result


## 下载清单并验签/核对选定身份；已安装版本重验通过可复用，否则逐文件下载、校验后安装。
## 每次可重入进度回调后仍可能收到取消；进入安装前再次检查，不发布半完成目录。
func _download_into(store: RefCounted, base_url: String, work: String, validator: Validation, selected: Dictionary = {}, mismatch_error: String = "channel_release_mismatch") -> Dictionary:
	for metadata: Dictionary in [{"name": "manifest.json", "limit": Manifest.MAX_MANIFEST_BYTES}, {"name": "manifest.sig", "limit": 1024}]:
		var fetched := await _fetch(base_url + "/" + metadata.name, work.path_join(metadata.name), metadata.limit, "manifest")
		if not fetched.ok:
			return fetched
	var bytes := FileAccess.get_file_as_bytes(work.path_join("manifest.json"))
	var signature := FileAccess.get_file_as_bytes(work.path_join("manifest.sig"))
	var verified: Dictionary = store.verify_manifest(bytes, signature)
	if not verified.ok:
		return verified
	_release = str(verified.value.release)
	if not selected.is_empty() and (_release != selected.release or Manifest.digest(bytes).hex_encode() != selected.manifest_sha256):
		return Manifest.failure(mismatch_error)
	# 固定发布地址与频道入口使用相同的失败版本隔离规则。
	# 同一 release 不可变，重复安装不能修复它导致的启动失败。
	if store.state_snapshot().rejected == _release:
		return Manifest.failure("release_rejected")
	for entry: Dictionary in verified.value.files:
		_total_bytes += int(entry.bytes)
	if _cancelled:
		return _cancel_result()
	var existing: Dictionary = store.check_installed(bytes, signature, validator)
	if not existing.ok:
		return existing
	if existing.installed:
		_completed_bytes = _total_bytes
		return {"ok": true, "release": _release, "already_installed": true, "error": ""}
	for entry: Dictionary in verified.value.files:
		var target := work.path_join(entry.path)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			return Manifest.failure("download_directory")
		var fetched := await _fetch(base_url + "/" + entry.path, target, int(entry.bytes), "downloading")
		if not fetched.ok:
			return fetched
		var checked: Dictionary = Manifest.verify_file(target, entry)
		if not checked.ok:
			return checked
		_completed_bytes += int(entry.bytes)
		_emit_progress("verified", entry.path)
	if _cancelled:
		return _cancel_result()
	_emit_progress("installing")
	if _cancelled:
		return _cancel_result()
	return store.install(work, bytes, signature, validator)


## 只重试连接/临时服务失败；签名、结构、哈希与磁盘错误不做盲目重试。
func _fetch(url: String, target: String, byte_limit: int, phase: String) -> Dictionary:
	var attempts := clampi(max_attempts, 1, 5)
	for attempt in range(1, attempts + 1):
		if _cancelled or not is_inside_tree():
			return _cancel_result()
		var result := await _fetch_once(url, target, byte_limit, phase, attempt)
		if result.ok or result.get("cancelled", false):
			return result
		result["attempts"] = attempt
		if not result.get("retryable", false) or attempt == attempts:
			return result
		_emit_progress("retry_wait", target.get_file(), 0, attempt)
		var deadline := Time.get_ticks_msec() + int(clampf(retry_delay_seconds, 0.0, 2.0) * pow(2.0, attempt - 1) * 1000.0)
		while Time.get_ticks_msec() < deadline and not _cancelled and is_inside_tree():
			await get_tree().process_frame
	return Manifest.failure("download_attempts")


## 执行一次禁重定向、禁压缩、限字节数的 HTTP 请求，先写 .part；成功才改名为待验证文件。
## mailbox 由完成信号写入，逐帧轮询同时检查取消和节点存活，避免直接 await 一个可能永不发出的信号。
func _fetch_once(url: String, target: String, byte_limit: int, phase: String, attempt: int) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = clampf(timeout_seconds, 0.1, 120.0)
	request.max_redirects = 0
	request.accept_gzip = false
	request.body_size_limit = byte_limit
	request.download_file = target + ".part"
	add_child(request)
	_request = request
	# Array 作为可变邮箱被 lambda 共享；回调只填结果，资源释放和重试决策仍留在外层任务。
	var mailbox: Array = [null]
	request.request_completed.connect(
		func(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			mailbox[0] = [result, status]
	)
	_emit_progress(phase, target.get_file(), 0, attempt)
	var error := request.request(url, ["Accept-Encoding: identity"])
	if error != OK:
		request.queue_free()
		_request = null
		return {"ok": false, "error": "http_start", "retryable": false}
	var last_bytes := -1
	while mailbox[0] == null and not _cancelled and is_inside_tree():
		var transferred := request.get_downloaded_bytes()
		if transferred != last_bytes:
			last_bytes = transferred
			_emit_progress(phase, target.get_file(), transferred, attempt)
		await get_tree().process_frame
	if _cancelled or not is_inside_tree():
		request.cancel_request()
		request.queue_free()
		_request = null
		return _cancel_result()
	var response: Array = mailbox[0]
	request.queue_free()
	_request = null
	var transport := int(response[0])
	var status := int(response[1])
	if transport != HTTPRequest.RESULT_SUCCESS or status != 200:
		var transient := transport in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_NO_RESPONSE, HTTPRequest.RESULT_TIMEOUT]
		# 错误页可能大于小 JSON 的限额；已知 503/429 状态仍可有限重试，不能放宽成功载荷上限。
		var retry_status := status in [408, 429] or (status >= 500 and status < 600)
		transient = transient or (retry_status and transport in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED])
		return {"ok": false, "error": "http_response:%d:%d" % [transport, status], "retryable": transient, "http_status": status, "transport": transport}
	if DirAccess.rename_absolute(target + ".part", target) != OK:
		return Manifest.failure("download_commit")
	return {"ok": true, "error": ""}


## 更新阶段、发布、文件、已验字节和尝试序号；发出独立快照供页面显示。
func _emit_progress(phase: String, file: String = "", file_bytes: int = 0, attempt: int = 0) -> void:
	_progress = {
		"phase": phase, "release": _release, "file": file,
		"completed_bytes": _completed_bytes, "total_bytes": _total_bytes,
		"file_bytes": file_bytes, "attempt": attempt,
	}
	progress_changed.emit(_progress.duplicate(true))


## 统一取消回执：ok=false 且 cancelled=true，外层据此显示取消而非成功或普通失败。
static func _cancel_result() -> Dictionary:
	return {"ok": false, "error": "download_cancelled", "cancelled": true}


## 复用频道入口的 URL 限制；测试 HTTP 也只允许显式开启后的 loopback 地址。
static func _allowed_url(url: String, allow_local_http: bool) -> bool:
	return Channel.allowed_url(url, allow_local_http)
