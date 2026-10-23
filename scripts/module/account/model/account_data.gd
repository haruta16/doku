## 账号模块的本地记录：保存手动登录渠道，以及是否仍需重建游客账号。
## 写入 user://account.cfg；它记录登录流程状态，不承载关卡或道具存档。

extends RefCounted
class_name AccountData

const _PATH: String = "user://account.cfg"

const _SECTION: String = "account"

var _signed_in_channel: String = ""

var _guest_reset_pending: bool = false


## 从账号专用配置文件还原渠道和游客重建标记；缺失字段沿用默认值。
func load_data() -> void:
	_signed_in_channel = ""
	_guest_reset_pending = false
	var cfg := ConfigFile.new()
	if cfg.load(_PATH) == OK:
		_signed_in_channel = str(cfg.get_value(_SECTION, "signed_in_channel", ""))
		_guest_reset_pending = bool(cfg.get_value(_SECTION, "guest_reset_pending", false))


func get_signed_in_channel() -> String:
	return _signed_in_channel


func set_signed_in_channel(ch: String) -> void:
	if ch.is_empty() or _signed_in_channel == ch:
		return
	_signed_in_channel = ch
	_save()


func clear_signed_in_channel() -> void:
	if _signed_in_channel.is_empty():
		return
	_signed_in_channel = ""
	_save()


func is_guest_reset_pending() -> bool:
	return _guest_reset_pending


func set_guest_reset_pending(pending: bool) -> void:
	if _guest_reset_pending == pending:
		return
	_guest_reset_pending = pending
	_save()


## 把账号流程字段写入 ConfigFile；调用 set_* 时会立即持久化。
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_PATH)
	cfg.set_value(_SECTION, "signed_in_channel", _signed_in_channel)
	cfg.set_value(_SECTION, "guest_reset_pending", _guest_reset_pending)
	cfg.save(_PATH)


## 清空账号内存记录并删除账号配置文件；不直接删除游戏关卡数据。
func clear() -> void:
	_signed_in_channel = ""
	_guest_reset_pending = false
	if FileAccess.file_exists(_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_PATH))
