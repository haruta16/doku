## 推荐服务的 HTTP 传输层；设置请求头与超时并发送 JSON，向协议层返回 ApiResponse。

class_name RecHttp
extends Node

const _TIMEOUT_SEC: float = 15.0

const _DEBUG_ENTRY_VALUE: String = "22ded59925bf903eccb78b0f6d6b556b"

static var override_luid: String = "6809c02cd8cb47019e9fdab0470e4f31"
static var override_learnings_id: String = "94c56f527a87aba6460cff7d0c40dde2"
static var override_device_id: String = "2db83840ef237af2"
static var override_country: String = "CN"
static var override_app_version: String = "1.14.0"


func post(path: String, body: Dictionary) -> Dictionary:
	if not UniKitManager.is_online():
		print("[RecHttp] 离线,跳过请求 (path=%s)" % path)
		return {"ok": false, "http_status": 0, "code": -1, "message": "offline", "data": {}}

	var body_json: String = JSON.stringify(body)
	var ts: int = int(Time.get_unix_time_from_system())
	var sign: String = (body_json + str(ts) + ApiConfig.sign_secret()).md5_text()
	var url: String = "%s%s?timestamp=%d&sign=%s" % [ApiConfig.rec_base_url(), path, ts, sign]

	var headers: PackedStringArray = _build_headers()

	var log_body: Dictionary = body.duplicate()
	var history_value: Variant = log_body.get("recent_history_normalized_raw_facts")
	if history_value is Array:
		var history: Array = history_value
		log_body["recent_history_normalized_raw_facts"] = "<%d 条已省略>" % history.size()
	print("\n========== [RecHttp] 完整请求 ==========")
	print("URL: %s" % url)
	print("── Headers ──")
	for h: String in headers:
		print("  %s" % h)
	print("── Body ──")
	print(JSON.stringify(log_body, "  ", false))
	print("========================================")

	var req := HTTPRequest.new()
	req.timeout = _TIMEOUT_SEC
	add_child(req)

	var err: int = req.request(url, headers, HTTPClient.METHOD_POST, body_json)
	if err != OK:
		req.queue_free()
		return {
			"ok": false,
			"http_status": 0,
			"code": -1,
			"message": "request() err=%d" % err,
			"data": {}
		}

	var res: Array = await req.request_completed
	req.queue_free()

	var transport: int = int(res[0])
	var http_status: int = int(res[1])
	var body_bytes: PackedByteArray = res[3]

	if transport != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"http_status": http_status,
			"code": -1,
			"message": "transport result=%d http=%d" % [transport, http_status],
			"data": {}
		}

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

	print("[RecHttp] ← http=%d code=%d msg=%s" % [http_status, code, message])
	if code != ApiConfig.CODE_OK:
		print("[RecHttp] 响应原文: %s" % text.substr(0, 2000))

	return {"ok": true, "http_status": http_status, "code": code, "message": message, "data": data}


func _build_headers() -> PackedStringArray:
	var ver: String = UniKitManager.get_version_name()
	var plat: String = ApiConfig.platform()
	var country: String = UniKitManager.get_ab_country()
	var lid: String = UniKitManager.get_learnings_id()
	var did: String = ApiConfig.device_id()
	var luid: String = ApiConfig.luid()

	if OS.has_feature("editor"):
		if ver.is_empty() and not override_app_version.is_empty():
			ver = override_app_version
		if country.is_empty() and not override_country.is_empty():
			country = override_country
		if not override_learnings_id.is_empty():
			lid = override_learnings_id
		if not override_device_id.is_empty():
			did = override_device_id
		if not override_luid.is_empty():
			luid = override_luid

	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	headers.append("app: " + ApiConfig.APP_ID)
	headers.append("app-version: " + ver)
	headers.append("country: " + country)
	headers.append("platform: " + plat)
	headers.append("user-agent: %s %s/%s" % [plat, ApiConfig.APP_ID, ver])
	headers.append("learnings-id: " + lid)
	headers.append("device-id: " + did)
	headers.append("luid: " + luid)

	if OS.has_feature("dev") or OS.has_feature("pre"):
		headers.append("x-debug-entry: " + _DEBUG_ENTRY_VALUE)
	return headers
