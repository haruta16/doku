# 存档读写层：单槽 / 双槽轮换的加密 ConfigFile 原子写入与损坏回退，不关心存了什么内容
class_name SaveStore
extends RefCounted

# 读盘尝试次数（首次失败后最多再重试 2 次）
const _LOAD_ATTEMPTS: int = 3
# 两次读盘尝试之间等待的毫秒数
const _RETRY_DELAY_MS: int = 60

# ---- 由 GameState 注入的路径与口令（本类不写死任何路径） ----
# 加密口令，save_encrypted_pass / load_encrypted_pass 共用
var _password: String
# 存档目录，写盘前会 make_dir_recursive_absolute
var _dir: String
# true = 双槽轮换（玩家主存档），false = 单槽（残局快照）
var _dual_slot: bool
# 槽 A 路径
var _path_a: String
# 槽 B 路径（单槽模式下为空串）
var _path_b: String
# flag 文件路径：记录「最后一次写成功的槽」；空串表示不写 flag
var _flag_path: String
# 旧版存档路径：双槽都读不出来时的最后兜底
var _legacy_path: String


# 构造：口令与各路径全部由调用方注入，双槽/单槽行为由 dual_slot 决定
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


# 保存配置：单槽直接覆盖；双槽写「flag 之外」的那一槽，成功才翻转 flag，失败保留旧槽
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


# 读取配置：带重试的读盘，3 次都失败返回 null（默认值由调用方决定）
func load_config() -> ConfigFile:
	for attempt in _LOAD_ATTEMPTS:
		var cfg := _load_once()
		if cfg != null:
			return cfg
		if attempt < _LOAD_ATTEMPTS - 1:
			OS.delay_msec(_RETRY_DELAY_MS)
	return null # 重试全部失败才算读档失败


# 删除存档：只清槽 A 及其 .tmp（单槽数据用，玩家双槽存档不会被删）
func remove() -> void:
	for p in [_path_a, _path_a + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# 单次读取尝试：单槽直读；双槽按 flag 定主备槽，主槽坏了退备槽，再退旧版存档
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


# 原子写：先写 <目标>.tmp 并回读校验，再 rename 覆盖目标，避免写一半崩溃损坏存档
func _atomic_write(cfg: ConfigFile, final_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir)
	var tmp_path := final_path + ".tmp"
	if cfg.save_encrypted_pass(tmp_path, _password) != OK:
		return false
	var verify := ConfigFile.new()
	if verify.load_encrypted_pass(tmp_path, _password) != OK:
		return false
	return DirAccess.rename_absolute(tmp_path, final_path) == OK # rename 成功才算写盘成功


# 读 flag 文件：只认 "A"/"B"，文件缺失或内容异常一律返回空串
func _read_flag() -> String:
	if not FileAccess.file_exists(_flag_path):
		return ""
	var f := FileAccess.open(_flag_path, FileAccess.READ)
	if f == null:
		return ""
	var flag := f.get_as_text().strip_edges()
	return flag if flag in ["A", "B"] else ""


# 写 flag 文件：标记本次写成功的槽；失败只报错，不影响已落盘的存档
func _write_flag(slot: String) -> void:
	var f := FileAccess.open(_flag_path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveStore] 写入 flag 文件失败")
		return
	f.store_string(slot) # 不写换行，读取端 strip_edges 容错
