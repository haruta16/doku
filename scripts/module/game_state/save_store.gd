## 存档文件存取：双槽轮换保护玩家档，单槽保存残局；临时文件验证成功后才替换正式文件。
class_name SaveStore
extends RefCounted

## 读盘尝试次数（首次失败后最多再重试 2 次）
const _LOAD_ATTEMPTS: int = 3
## 两次读盘尝试之间等待的毫秒数
const _RETRY_DELAY_MS: int = 60

# ---- 由 GameState 注入的路径与口令（本类不写死任何路径） ----
## 加密口令，save_encrypted_pass / load_encrypted_pass 共用
var _password: String
## 存档目录，写盘前会 make_dir_recursive_absolute
var _dir: String
## true = 双槽轮换（玩家主存档），false = 单槽（残局快照）
var _dual_slot: bool
## 槽 A 路径
var _path_a: String
## 槽 B 路径（单槽模式下为空串）
var _path_b: String
## flag 文件路径：记录「最后一次写成功的槽」；空串表示不写 flag
var _flag_path: String
## 旧版存档路径：双槽都读不出来时的最后兜底
var _legacy_path: String
var _encrypted: bool = true


## 创建不加密的单文件存储实例，供需要普通 ConfigFile 的调用方使用。
static func plain_file(path: String) -> SaveStore:
	var store: SaveStore = SaveStore.new("", path.get_base_dir(), false, path)
	store._encrypted = false
	return store


## 构造：口令与各路径全部由调用方注入，双槽/单槽行为由 dual_slot 决定
func _init(
	password: String,
	dir: String,
	dual_slot: bool,
	path_a: String,
	path_b: String = "",
	flag_path: String = "",
	legacy_path: String = ""
) -> void:
	_password = password
	_dir = dir
	_dual_slot = dual_slot
	_path_a = path_a
	_path_b = path_b
	_flag_path = flag_path
	_legacy_path = legacy_path


## 保存配置：单槽直接覆盖；双槽写「flag 之外」的那一槽，成功才翻转 flag，失败保留旧槽
func save_config(cfg: ConfigFile) -> bool:
	if not _dual_slot:
		return _atomic_write(cfg, _path_a)
	var last_good := _read_flag()
	var target: String = "A" if last_good != "A" else "B" # 挑上一次没写的那一槽
	var final_path: String = _path_a if target == "A" else _path_b
	if _atomic_write(cfg, final_path):
		_write_flag(target)
		return true
	push_error("[SaveStore] 原子写失败 slot=%s,保留旧槽,本次不切 flag" % target) # 写失败就不切 flag，旧槽仍是主槽
	return false


## 读取配置：带重试的读盘，3 次都失败返回 null（默认值由调用方决定）
func load_config() -> ConfigFile:
	for attempt in _LOAD_ATTEMPTS:
		var cfg := _load_once()
		if cfg != null:
			return cfg
		if attempt < _LOAD_ATTEMPTS - 1:
			OS.delay_msec(_RETRY_DELAY_MS)
	return null # 重试全部失败才算读档失败


## 删除存档：只清槽 A 及其 .tmp（单槽数据用，玩家双槽存档不会被删）
func remove() -> void:
	for p in [_path_a, _path_a + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## 仅对没有临时写入的单槽文件捕获原始字节与存在状态，供事务回滚。
func capture_file_snapshot() -> Dictionary:
	if _dual_slot or FileAccess.file_exists(_path_a + ".tmp"):
		return {}
	var exists: bool = FileAccess.file_exists(_path_a)
	var content: PackedByteArray = PackedByteArray()
	if exists:
		var file: FileAccess = FileAccess.open(_path_a, FileAccess.READ)
		if file == null:
			return {}
		var length: int = file.get_length()
		content = file.get_buffer(length)
		file.close()
		if content.size() != length:
			return {}
	return {"path": _path_a, "exists": exists, "bytes": content}


## 验证快照路径和类型后恢复单槽文件，写临时文件并逐字节核对、重新解析后才替换。
func restore_file_snapshot(snapshot: Dictionary) -> bool:
	if (
		_dual_slot
		or snapshot.get("path", "") != _path_a
		or typeof(snapshot.get("exists")) != TYPE_BOOL
		or typeof(snapshot.get("bytes")) != TYPE_PACKED_BYTE_ARRAY
	):
		return false
	if not snapshot["exists"]:
		remove()
		return not FileAccess.file_exists(_path_a) and not FileAccess.file_exists(_path_a + ".tmp")
	if DirAccess.make_dir_recursive_absolute(_dir) != OK:
		return false
	var temporary: String = _path_a + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var content: PackedByteArray = snapshot["bytes"]
	file.store_buffer(content)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_bytes(temporary) != content:
		return false
	var verified: ConfigFile = ConfigFile.new()
	if _read_config(verified, temporary) != OK:
		return false
	return DirAccess.rename_absolute(temporary, _path_a) == OK


## 单槽直接读取；双槽按 flag 优先读主槽，再尝试备槽和旧版存档。
func _load_once() -> ConfigFile:
	if not _dual_slot:
		var cfg := ConfigFile.new()
		if FileAccess.file_exists(_path_a) and _read_config(cfg, _path_a) == OK:
			return cfg
		return null

	var last_good := _read_flag()
	var primary: String = _path_b if last_good == "B" else _path_a
	var backup: String = _path_a if last_good == "B" else _path_b
	var config: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(primary):
		if _read_config(config, primary) == OK:
			return config
		push_error("[SaveStore] 主槽损坏: %s,尝试备槽" % primary)
	config = ConfigFile.new()
	if FileAccess.file_exists(backup):
		if _read_config(config, backup) == OK:
			push_error("[SaveStore] 已从备槽恢复: %s" % backup)
			return config
		push_error("[SaveStore] 双槽均损坏")
	if not _legacy_path.is_empty() and FileAccess.file_exists(_legacy_path):
		config = ConfigFile.new()
		if _read_config(config, _legacy_path) == OK:
			push_error("[SaveStore] 已从旧存档恢复: %s" % _legacy_path)
			return config
	return null


## 先写临时文件并重新读取校验，再重命名覆盖目标；明文模式还核对配置文本。
func _atomic_write(cfg: ConfigFile, final_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir)
	var tmp_path := final_path + ".tmp"
	var write_error: int = (
		cfg.save_encrypted_pass(tmp_path, _password) if _encrypted else cfg.save(tmp_path)
	)
	if write_error != OK:
		return false
	var verify := ConfigFile.new()
	if _read_config(verify, tmp_path) != OK:
		return false
	if not _encrypted and verify.encode_to_text() != cfg.encode_to_text():
		return false
	return DirAccess.rename_absolute(tmp_path, final_path) == OK


## 根据实例的加密开关选择口令解密或普通配置读取。
func _read_config(cfg: ConfigFile, path: String) -> int:
	return cfg.load_encrypted_pass(path, _password) if _encrypted else cfg.load(path)


## 读 flag 文件：只认 "A"/"B"，文件缺失或内容异常一律返回空串
func _read_flag() -> String:
	if not FileAccess.file_exists(_flag_path):
		return ""
	var f := FileAccess.open(_flag_path, FileAccess.READ)
	if f == null:
		return ""
	var flag := f.get_as_text().strip_edges()
	return flag if flag in ["A", "B"] else ""


## 写 flag 文件：标记本次写成功的槽；失败只报错，不影响已落盘的存档
func _write_flag(slot: String) -> void:
	var f := FileAccess.open(_flag_path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveStore] 写入 flag 文件失败")
		return
	f.store_string(slot) # 不写换行，读取端 strip_edges 容错
