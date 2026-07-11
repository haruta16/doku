class_name DebugApiServer
extends RefCounted

const _RECV_BUFFER_SIZE: int = 8192
const _MAX_HEADER_SIZE: int = 16384
const _CONNECTION_TIMEOUT_MS: int = 5000

var _server: TCPServer = null
var _routes: Dictionary = {}
var _connections: Array = []
var _is_running: bool = false
var _port: int = 0


func start(port: int) -> Error:
	if _is_running:
		push_warning("DebugApiServer: already running on port %d" % _port)
		return OK
	_server = TCPServer.new()

	var err: int = _server.listen(port, "0.0.0.0")
	if err != OK:
		push_error("DebugApiServer: listen failed on port %d, err=%d" % [port, err])
		_server = null
		return err
	_port = port
	_is_running = true
	print("DebugApiServer: listening on 0.0.0.0:%d" % port)
	return OK


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


func is_running() -> bool:
	return _is_running


func register_route(path: String, handler: Callable) -> void:
	if not handler.is_valid():
		push_error("DebugApiServer: register_route invalid handler for %s" % path)
		return
	_routes[path] = handler


func get_routes() -> Array:
	return _routes.keys()


func poll() -> void:
	if not _is_running or _server == null:
		return

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

	var alive: Array = []
	for conn in _connections:
		if _process_connection(conn):
			alive.append(conn)
		else:
			(conn["peer"] as StreamPeerTCP).disconnect_from_host()
	_connections = alive


func _process_connection(conn: Dictionary) -> bool:
	var peer: StreamPeerTCP = conn["peer"]
	peer.poll()
	var status: int = peer.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		return false

	if Time.get_ticks_msec() - int(conn["started_at"]) > _CONNECTION_TIMEOUT_MS:
		return false

	var buffer: PackedByteArray = conn["buffer"]

	var available: int = peer.get_available_bytes()
	if available > 0:
		var to_read: int = min(available, _RECV_BUFFER_SIZE)
		var chunk: Array = peer.get_partial_data(to_read)
		if chunk[0] == OK:
			buffer.append_array(chunk[1])
			conn["buffer"] = buffer

	if buffer.size() > _MAX_HEADER_SIZE:
		return false

	var header_end: int = _find_header_end(buffer)
	if header_end < 0:
		return true

	var raw: String = buffer.slice(0, header_end).get_string_from_ascii()
	var ctx: DebugApiContext = _parse_request(raw)
	if ctx == null:
		_write_response(
			peer, _build_response_string(400, '{"result":"error","message":"Bad Request"}')
		)
		return false

	_dispatch(ctx)
	_write_response(peer, _build_response_string(ctx.status_code, ctx.response_body))
	return false


func _parse_request(raw: String) -> DebugApiContext:
	var lines: PackedStringArray = raw.split("\r\n")
	if lines.size() == 0:
		return null

	var first: String = lines[0]
	var parts: PackedStringArray = first.split(" ")
	if parts.size() < 3:
		return null

	var ctx := DebugApiContext.new()
	ctx.method = parts[0]

	var raw_path: String = parts[1]
	var q_idx: int = raw_path.find("?")
	if q_idx >= 0:
		ctx.path = raw_path.substr(0, q_idx)
		ctx.query_params = _parse_query(raw_path.substr(q_idx + 1))
	else:
		ctx.path = raw_path

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


func _parse_query(qs: String) -> Dictionary:
	var out: Dictionary = {}
	if qs.is_empty():
		return out
	var pairs: PackedStringArray = qs.split("&")
	for pair in pairs:
		if pair.is_empty():
			continue
		var eq: int = pair.find("=")
		if eq < 0:
			out[pair.uri_decode()] = ""
		else:
			var k: String = pair.substr(0, eq).uri_decode()
			var v: String = pair.substr(eq + 1).uri_decode()
			out[k] = v
	return out


func _dispatch(ctx: DebugApiContext) -> void:
	if not _routes.has(ctx.path):
		ctx.status_code = 404
		ctx.response_body = JSON.stringify(
			{"result": "error", "message": "Not Found: %s" % ctx.path}
		)
		return

	var handler: Callable = _routes[ctx.path]

	handler.call(ctx)


func _build_response_string(code: int, body: String) -> String:
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


func _write_response(peer: StreamPeerTCP, response: String) -> void:
	var bytes: PackedByteArray = response.to_utf8_buffer()
	var sent: int = 0
	while sent < bytes.size():
		var slice: PackedByteArray = bytes.slice(sent, bytes.size())
		var res: Array = peer.put_partial_data(slice)
		if res[0] != OK:
			return
		var n: int = int(res[1])
		if n == 0:
			break
		sent += n


func _find_header_end(buf: PackedByteArray) -> int:
	var n: int = buf.size()
	for i in range(n - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


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
