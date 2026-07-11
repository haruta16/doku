class_name SaveStore
extends RefCounted

const _LOAD_ATTEMPTS: int = 3
const _RETRY_DELAY_MS: int = 60

var _password: String
var _dir: String
var _dual_slot: bool
var _path_a: String
var _path_b: String
var _flag_path: String
var _legacy_path: String


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


func save_config(cfg: ConfigFile) -> bool:
	if not _dual_slot:
		return _atomic_write(cfg, _path_a)
	var last_good := _read_flag()
	var target: String = "A" if last_good != "A" else "B"
	var final_path: String = _path_a if target == "A" else _path_b
	if _atomic_write(cfg, final_path):
		_write_flag(target)
		return true
	push_error("[SaveStore] 原子写失败 slot=%s,保留旧槽,本次不切 flag" % target)
	return false


func load_config() -> ConfigFile:
	for attempt in _LOAD_ATTEMPTS:
		var cfg := _load_once()
		if cfg != null:
			return cfg
		if attempt < _LOAD_ATTEMPTS - 1:
			OS.delay_msec(_RETRY_DELAY_MS)
	return null


func remove() -> void:
	for p in [_path_a, _path_a + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _load_once() -> ConfigFile:
	if not _dual_slot:
		var cfg := ConfigFile.new()
		if FileAccess.file_exists(_path_a) and cfg.load_encrypted_pass(_path_a, _password) == OK:
			return cfg
		return null

	var last_good := _read_flag()
	var primary: String = _path_b if last_good == "B" else _path_a
	var backup: String = _path_a if last_good == "B" else _path_b
	var c := ConfigFile.new()
	if FileAccess.file_exists(primary):
		if c.load_encrypted_pass(primary, _password) == OK:
			return c
		push_error("[SaveStore] 主槽损坏: %s,尝试备槽" % primary)
	c = ConfigFile.new()
	if FileAccess.file_exists(backup):
		if c.load_encrypted_pass(backup, _password) == OK:
			push_error("[SaveStore] 已从备槽恢复: %s" % backup)
			return c
		push_error("[SaveStore] 双槽均损坏")
	if not _legacy_path.is_empty() and FileAccess.file_exists(_legacy_path):
		c = ConfigFile.new()
		if c.load_encrypted_pass(_legacy_path, _password) == OK:
			push_error("[SaveStore] 已从旧存档恢复: %s" % _legacy_path)
			return c
	return null


func _atomic_write(cfg: ConfigFile, final_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir)
	var tmp_path := final_path + ".tmp"
	if cfg.save_encrypted_pass(tmp_path, _password) != OK:
		return false
	var verify := ConfigFile.new()
	if verify.load_encrypted_pass(tmp_path, _password) != OK:
		return false
	return DirAccess.rename_absolute(tmp_path, final_path) == OK


func _read_flag() -> String:
	if not FileAccess.file_exists(_flag_path):
		return ""
	var f := FileAccess.open(_flag_path, FileAccess.READ)
	if f == null:
		return ""
	var flag := f.get_as_text().strip_edges()
	return flag if flag in ["A", "B"] else ""


func _write_flag(slot: String) -> void:
	var f := FileAccess.open(_flag_path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveStore] 写入 flag 文件失败")
		return
	f.store_string(slot)
