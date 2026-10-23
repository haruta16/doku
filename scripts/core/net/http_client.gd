## 业务 JSON 客户端：生成请求签名、补公共请求头，并用服务端日期校正本机时钟。
class_name HttpClient
extends Node

const _TIMEOUT_SEC: float = 10.0

const _CLOCK_SKEW_RETRY_THRESHOLD_SEC: int = 3

static var _server_time_offset_sec: int = 0
static var _has_server_time: bool = false


## 返回校准后的 Unix 秒时间；尚未收到服务端时间时返回 -1。
static func calibrated_unix_time() -> int:
	if not _has_server_time:
		return -1
	return int(Time.get_unix_time_from_system()) + _server_time_offset_sec


## 发送业务请求；签名或时间错误且新时差至少变化 3 秒时，只重试一次。
func request_json(
	method: int, path: String, body: Dictionary = {}, bearer: String = ""
) -> ApiResponse:
	if not UniKitManager.is_online():
		return _net_fail("offline")

	var raw_body: String = ""
	if method != HTTPClient.METHOD_GET and not body.is_empty():
		raw_body = JSON.stringify(body)

	var response: ApiResponse = await _send(method, path, raw_body, bearer)

	if (
		response.ok
		and response.code in [ApiConfig.CODE_SIGN_INVALID, ApiConfig.CODE_TIMESTAMP_EXPIRED]
	):
		if (
			absi(_server_time_offset_sec - response.sign_offset_sec)
			>= _CLOCK_SKEW_RETRY_THRESHOLD_SEC
		):
			print(
				(
					"[HttpClient] code=%d + 服务端时间校正(off %ds→%ds)，用校正时间重试一次"
					% [response.code, response.sign_offset_sec, _server_time_offset_sec]
				)
			)
			response = await _send(method, path, raw_body, bearer)
	return response


## 创建一次 HTTPRequest，等待后释放节点，并把响应拆成统一 ApiResponse。
func _send(method: int, path: String, raw_body: String, bearer: String) -> ApiResponse:
	var used_offset: int = _server_time_offset_sec

	var ts: int = int(Time.get_unix_time_from_system()) + used_offset
	var sign: String = (raw_body + str(ts) + ApiConfig.sign_secret()).md5_text()
	var url: String = "%s%s?timestamp=%d&sign=%s" % [ApiConfig.base_url(), path, ts, sign]

	var headers: PackedStringArray = _common_headers()
	if not bearer.is_empty():
		headers.append("Authorization: " + bearer)

	print(
		(
			"[HttpClient] → %s %s ts=%d(off=%d) sign=%s body_len=%d bearer=%s"
			% [
				_method_name(method),
				path,
				ts,
				used_offset,
				sign,
				raw_body.length(),
				("yes(len=%d)" % bearer.length()) if not bearer.is_empty() else "NO"
			]
		)
	)

	var req := HTTPRequest.new()
	req.timeout = _TIMEOUT_SEC
	add_child(req)

	var err: int = req.request(url, headers, method, raw_body)
	if err != OK:
		req.queue_free()
		return _net_fail("request() err=%d" % err)

	var res: Array = await req.request_completed
	req.queue_free()

	var transport: int = int(res[0])
	var http_status: int = int(res[1])
	var resp_headers: PackedStringArray = res[2]
	var body_bytes: PackedByteArray = res[3]
	_calibrate_offset(resp_headers)
	if transport != HTTPRequest.RESULT_SUCCESS:
		return _net_fail("transport result=%d http=%d" % [transport, http_status])

	var text: String = body_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var envelope: Dictionary = parsed if parsed is Dictionary else {}
	var status: Dictionary = (
		envelope.get("status", {}) if envelope.get("status", {}) is Dictionary else {}
	)
	var code: int = int(status.get("code", -1))
	var message: String = str(status.get("message", ""))
	var data_raw: Variant = envelope.get("data", {})
	var data: Dictionary = data_raw if data_raw is Dictionary else {}

	print(
		(
			"[HttpClient] ← %s %s http=%d code=%d msg=%s"
			% [_method_name(method), path, http_status, code, message]
		)
	)

	return ApiResponse.received(http_status, code, message, data, used_offset)


## 读取响应 Date 头，更新所有 HttpClient 实例共用的服务端秒级时差。
func _calibrate_offset(resp_headers: PackedStringArray) -> void:
	for h in resp_headers:
		var idx: int = h.find(":")
		if idx < 0:
			continue
		if h.substr(0, idx).strip_edges().to_lower() != "date":
			continue
		var server_unix: int = HttpDate.parse_imf_fixdate(h.substr(idx + 1).strip_edges())
		if server_unix > 0:
			var new_off: int = server_unix - int(Time.get_unix_time_from_system())
			if absi(new_off - _server_time_offset_sec) >= 1:
				print("[HttpClient] 服务端时间校准：offset %ds → %ds" % [_server_time_offset_sec, new_off])
			_server_time_offset_sec = new_off
			_has_server_time = true
		return


## 从版本、实验地区、统计与认证模块收集请求头标识。
func _common_headers() -> PackedStringArray:
	var ver: String = UniKitManager.get_version_name()
	var plat: String = ApiConfig.platform()
	var country: String = UniKitManager.get_ab_country()
	var lid: String = UniKitManager.get_learnings_id()
	var did: String = ApiConfig.device_id()
	var luid: String = ApiConfig.luid()

	if OS.is_debug_build():
		print(
			(
				"[HttpClient] hdr app-version=%s country=%s platform=%s learnings-id=%s device-id=%s luid=%s"
				% [ver, country, plat, lid, did, luid]
			)
		)
	var h := PackedStringArray()
	h.append("Content-Type: application/json")
	h.append("app: " + ApiConfig.APP_ID)
	h.append("app-version: " + ver)
	h.append("country: " + country)
	h.append("platform: " + plat)
	h.append("user-agent: %s %s/%s" % [plat, ApiConfig.APP_ID, ver])
	h.append("learnings-id: " + lid)

	h.append("device-id: " + did)
	h.append("luid: " + luid)
	return h


## 把常见请求方法转成日志名称，未知方法保留数值便于排查。
func _method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
		_:
			return "M%d" % method


## 记录传输失败原因并返回失败对象，不把网络错误伪装成业务响应。
func _net_fail(reason: String) -> ApiResponse:
	push_warning("HttpClient request failed: " + reason)
	return ApiResponse.net_fail(reason)
