## 回流调试标记：为下一次冷启动写入一次性的实验组覆盖，读取后删除文件。
class_name ComebackCheat
extends RefCounted

const _PATH: String = "user://cheat_comeback.cfg"
const _SECTION: String = "comeback"
const _GROUP_KEY: String = "next_cold_start_group"


## 非发布构建将调试分组写入 user 目录，供下一次冷启动读取。
static func arm_next_cold_start(group: int) -> void:
	if OS.has_feature("rel"):
		return
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, _GROUP_KEY, group)
	var err: int = cfg.save(_PATH)
	if err != OK:
		push_error("[ComebackCheat] 写 %s 失败 err=%d" % [_PATH, err])


## 读取后立即删除覆盖文件，保证同一调试标记只影响一次冷启动。
static func consume_next_cold_start() -> int:
	if OS.has_feature("rel") or not FileAccess.file_exists(_PATH):
		return -1
	var cfg := ConfigFile.new()
	var group: int = -1
	if cfg.load(_PATH) == OK:
		group = int(cfg.get_value(_SECTION, _GROUP_KEY, -1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_PATH))
	return group
