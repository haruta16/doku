# 极简 HTTP/1.1 服务器：listen / poll / 解析 / 路由 / 回包都在这一个文件里，只服务调试 API
# 只做普通 HTTP，没有 WebSocket：一条连接处理完一个请求就断开
class_name DebugApiServer
extends RefCounted

# ---- 参数（数值单位见注释） ----
const _RECV_BUFFER_SIZE: int = 8192 # 单次读 socket 的上限（字节）
const _MAX_HEADER_SIZE: int = 16384 # 请求头最大长度（字节），超了直接断连
const _CONNECTION_TIMEOUT_MS: int = 5000 # 单条连接从建立到必须处理完的超时（毫秒）

# ---- 运行时状态 ----
var _server: TCPServer = null # TCPServer 本体，stop() 后置回 null
var _routes: Dictionary = {} # 路由表：path（含 /meowdoku/api 前缀）→ 处理函数
var _connections: Array = [] # 活跃连接，每项 {peer, buffer, started_at}
var _is_running: bool = false # 是否已 listen 成功
var _port: int = 0 # 实际监听端口，0 表示还没起


# ================= 生命周期 =================
# 开始监听 0.0.0.0:port；已在跑就原样返回 OK，失败则清空 socket 并返回错误码
func start(port: int) -> Error:
	if _is_running:
		push_warning("DebugApiServer: already running on port %d" % _port)
		return OK
	_server = TCPServer.new()

	# 监听所有网卡，方便真机 / 模拟器连过来
	var err: int = _server.listen(port, "0.0.0.0")
	if err != OK:
		push_error("DebugApiServer: listen failed on port %d, err=%d" % [port, err])
		_server = null
		return err
	_port = port
	_is_running = true
	print("DebugApiServer: listening on 0.0.0.0:%d" % port)
	return OK


# 停止监听并断开所有连接；没在跑就什么都不做
func stop() -> void:
	if not _is_running:
		return
	_is_running = false
	if _server != null:
		_server.stop()
		_server = null
	for conn in _connections:
		var peer: StreamPeerTCP = conn["peer"]
		peer.disconnect_from_host()
	_connections.clear()
	print("DebugApiServer: stopped")


# 查询是否正在监听（DebugApiServerManager 用它判断可用性）
func is_running() -> bool:
	return _is_running


# ================= 路由表 =================
# 注册一条路由；同 path 后注册的覆盖先前的，handler 无效则报错并忽略
func register_route(path: String, handler: Callable) -> void:
	if not handler.is_valid():
		push_error("DebugApiServer: register_route invalid handler for %s" % path)
		return
	_routes[path] = handler


# 返回所有已注册的 path（/routes 接口用它自省）
func get_routes() -> Array:
	return _routes.keys()


# ================= 轮询与连接处理 =================
# 由 DebugApiServerManager._process 每帧调用：收新连接 + 推进已有连接
func poll() -> void:
	if not _is_running or _server == null:
		return

	# 先把这一帧新到的连接全部收下，连同缓冲区和建立时间一起记
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			(
				_connections
				. append(
					{
						"peer": peer,
						"buffer": PackedByteArray(),
						"started_at": Time.get_ticks_msec(),
					}
				)
			)

	# 再逐条推进：返回 false 的（出错 / 超时 / 已处理完）立刻断开
	var alive: Array = []
	for conn in _connections:
		if _process_connection(conn):
			alive.append(conn)
		else:
			(conn["peer"] as StreamPeerTCP).disconnect_from_host()
	_connections = alive


# 推进单条连接；返回 true 表示还要保持（请求头还没收全）
func _process_connection(conn: Dictionary) -> bool:
	var peer: StreamPeerTCP = conn["peer"]
	peer.poll()
	var status: int = peer.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		return false

	# 超时保护：慢连接不拖住主线程
	if Time.get_ticks_msec() - int(conn["started_at"]) > _CONNECTION_TIMEOUT_MS:
		return false

	var buffer: PackedByteArray = conn["buffer"]

	# 有数据就追加进该连接的缓冲区
	var available: int = peer.get_available_bytes()
	if available > 0:
		var to_read: int = min(available, _RECV_BUFFER_SIZE) # 一次最多读 8KB
		var chunk: Array = peer.get_partial_data(to_read)
		if chunk[0] == OK:
			buffer.append_array(chunk[1])
			conn["buffer"] = buffer

	# 请求头过大当成异常连接，直接断开
	if buffer.size() > _MAX_HEADER_SIZE:
		return false

	# 还没收到空行结尾说明头没收全，留到下一帧再试
	var header_end: int = _find_header_end(buffer)
	if header_end < 0:
		return true

	# 只取请求头部分解析（本项目不支持请求体）
	var raw: String = buffer.slice(0, header_end).get_string_from_ascii()
	var ctx: DebugApiContext = _parse_request(raw)
	if ctx == null:
		_write_response(
			peer, _build_response_string(400, '{"result":"error","message":"Bad Request"}')
		)
		return false

	# 交给路由处理，再把 ctx 上的状态码与响应体写回去
	_dispatch(ctx)
	_write_response(peer, _build_response_string(ctx.status_code, ctx.response_body))
	return false


# ================= HTTP 解析 =================
# 解析请求行与请求头；格式不对返回 null
func _parse_request(raw: String) -> DebugApiContext:
	var lines: PackedStringArray = raw.split("\r\n")
	if lines.size() == 0:
		return null

	# 请求行形如 GET /path?x=1 HTTP/1.1
	var first: String = lines[0]
	var parts: PackedStringArray = first.split(" ")
	if parts.size() < 3:
		return null

	var ctx := DebugApiContext.new()
	ctx.method = parts[0]

	# 路径与查询串在第一个问号处切开
	var raw_path: String = parts[1]
	var q_idx: int = raw_path.find("?")
	if q_idx >= 0:
		ctx.path = raw_path.substr(0, q_idx)
		ctx.query_params = _parse_query(raw_path.substr(q_idx + 1))
	else:
		ctx.path = raw_path

	# 逐行收请求头，遇到空行就结束
	for i in range(1, lines.size()):
		var line: String = lines[i].strip_edges()
		if line.is_empty():
			break
		var colon: int = line.find(":")
		if colon > 0:
			var k: String = line.substr(0, colon).strip_edges()
			var v: String = line.substr(colon + 1).strip_edges()
			ctx.headers[k] = v

	return ctx


# 把 a=1&b=2 解析成字典：键值都做 URI 解码，没有等号的键值为空串
func _parse_query(qs: String) -> Dictionary:
	var out: Dictionary = {}
	if qs.is_empty():
		return out
	var pairs: PackedStringArray = qs.split("&")
	for pair in pairs:
		if pair.is_empty():
			continue
		var eq: int = pair.find("=")
		# 没有等号的键按空值处理
		if eq < 0:
			out[pair.uri_decode()] = ""
		else:
			var k: String = pair.substr(0, eq).uri_decode()
			var v: String = pair.substr(eq + 1).uri_decode()
			out[k] = v
	return out


# ================= 分发与回包 =================
# 按 path 找处理函数并调用；找不到就回 404
func _dispatch(ctx: DebugApiContext) -> void:
	# 未注册的 path 统一回 404 JSON
	if not _routes.has(ctx.path):
		ctx.status_code = 404
		ctx.response_body = JSON.stringify(
			{"result": "error", "message": "Not Found: %s" % ctx.path}
		)
		return

	var handler: Callable = _routes[ctx.path]

	# 处理函数自己负责调 ctx.set_json / set_error
	handler.call(ctx)


# 拼完整 HTTP 响应：JSON 头、CORS 全放开、Content-Length 按字节算、短连接
func _build_response_string(code: int, body: String) -> String:
	# Content-Length 必须按 UTF-8 字节数算，带中文才不会截断
	var byte_len: int = body.to_utf8_buffer().size()
	var lines := PackedStringArray()
	lines.append("HTTP/1.1 %d %s" % [code, _status_reason(code)])
	lines.append("Content-Type: application/json; charset=utf-8")
	lines.append("Content-Length: %d" % byte_len)
	lines.append("Access-Control-Allow-Origin: *")
	lines.append("Connection: close")
	lines.append("")
	lines.append(body)
	return "\r\n".join(lines)


# 循环写直到写完（put_partial_data 一次可能只写一部分）
func _write_response(peer: StreamPeerTCP, response: String) -> void:
	var bytes: PackedByteArray = response.to_utf8_buffer()
	var sent: int = 0
	while sent < bytes.size(): # 分包发送，直到全部写完
		var slice: PackedByteArray = bytes.slice(sent, bytes.size())
		var res: Array = peer.put_partial_data(slice)
		if res[0] != OK:
			return
		var n: int = int(res[1])
		if n == 0:
			break
		sent += n


# 逐字节找 CRLF CRLF（13/10/13/10）
func _find_header_end(buf: PackedByteArray) -> int:
	var n: int = buf.size()
	for i in range(n - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


# 状态码转原因短语；没列出的码统一按 OK 回
func _status_reason(code: int) -> String:
	match code:
		200:
			return "OK"
		400:
			return "Bad Request"
		404:
			return "Not Found"
		500:
			return "Internal Server Error"
	return "OK"
