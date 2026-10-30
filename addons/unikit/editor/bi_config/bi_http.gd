## 编辑器配置 HTTP 工具：通过 curl 同步拉取远端内容，并统一状态与错误信息。
@tool
class_name UniKitBIHttp
extends RefCounted

const _TIMEOUT_SEC := 20


## 发起有超时和重试上限的同步请求，只有成功状态且正文非空才标记成功。
static func get_sync(url: String, headers: Dictionary, max_retry: int = 5) -> Dictionary:
	var args := PackedStringArray(
		[
			"-sS",
			"-L",
			"-m",
			str(_TIMEOUT_SEC),
			"--retry",
			str(max(0, max_retry - 1)),
			"-w",
			"\n%{http_code}",
		]
	)
	for k in headers:
		args.append("-H")
		args.append("%s: %s" % [k, headers[k]])
	args.append(url)

	var out := []
	var rc := OS.execute("curl", args, out, true)
	if rc != 0:
		push_warning("[UniKitBIHttp] curl 退出码 %d url=%s" % [rc, url])
		return {"ok": false, "body": "", "code": -1}

	var raw := "\n".join(out)
	var nl := raw.rfind("\n")
	var code := -1
	var body := raw
	if nl >= 0:
		code = raw.substr(nl + 1).strip_edges().to_int()
		body = raw.substr(0, nl)
	var ok: bool = code >= 200 and code < 300 and body.length() > 0
	if not ok:
		push_warning("[UniKitBIHttp] HTTP code=%d body_len=%d url=%s" % [code, body.length(), url])
	return {"ok": ok, "body": body, "code": code}
