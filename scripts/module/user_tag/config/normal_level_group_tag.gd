## 普通关分组标签：协调开局、启动和云存档恢复后的写入，并处理 SDK 尚未就绪的待发更新。
class_name NormalLevelGroupTag
extends RefCounted

const LOCAL_TAG_KEY: String = "normal_level_group"
const NORMAL_LEVEL_GROUP_START_LEVELS: Array[int] = [1, 21, 51, 101, 201, 401, 601]
const ENABLED: bool = true

static var _pending_group_value: String = ""
static var _pending_cloud_restore_check: bool = false
static var _cloud_restore_revision: int = 0
static var _cloud_restore_query_in_flight: bool = false


static func normal_level_group_value_for_level(level_num: int) -> String:
	if level_num <= 0:
		return ""
	if level_num <= 20:
		return "1-20"
	if level_num <= 50:
		return "21-50"
	if level_num <= 100:
		return "51-100"
	if level_num <= 200:
		return "101-200"
	if level_num <= 400:
		return "201-400"
	if level_num <= 600:
		return "401-600"
	return "601+"


static func should_update_normal_level_group_at_level_start(
	level_num: int, is_normal_entry: bool, level_kind: int
) -> bool:
	if not is_normal_entry or LevelKind.is_golden_fish(level_kind):
		return false
	return NORMAL_LEVEL_GROUP_START_LEVELS.has(level_num)


static func should_update_normal_level_group_on_startup(
	persisted_group_value: String, is_new_user: bool, level_num: int
) -> bool:
	return (
		not is_new_user
		and persisted_group_value.is_empty()
		and not normal_level_group_value_for_level(level_num).is_empty()
	)


static func should_update_normal_level_group_after_cloud_restore(
	level_num: int, local_tags: Dictionary
) -> bool:
	var latest_group_value: String = normal_level_group_value_for_level(level_num)
	if latest_group_value.is_empty():
		return false
	var existing_value_raw: Variant = local_tags.get(LOCAL_TAG_KEY, "")
	var existing_group_value: String = existing_value_raw if existing_value_raw is String else ""
	return existing_group_value != latest_group_value


static func update_at_level_start(level_num: int, is_normal_entry: bool, level_kind: int) -> void:
	if not ENABLED:
		return
	if not should_update_normal_level_group_at_level_start(level_num, is_normal_entry, level_kind):
		return
	_write(level_num)


static func update_missing_tag_on_startup(level_num: int, is_new_user: bool) -> void:
	if not ENABLED:
		return
	_ensure_cloud_restore_binding()
	var persisted_group_value: String = GameState.get_persisted_user_tag(LOCAL_TAG_KEY)
	if not should_update_normal_level_group_on_startup(
		persisted_group_value, is_new_user, level_num
	):
		if (
			not is_new_user
			and persisted_group_value.is_empty()
			and normal_level_group_value_for_level(level_num).is_empty()
		):
			push_warning("[normal_level_group] invalid main level=%d, skip local tag" % level_num)
		return
	var group_value: String = normal_level_group_value_for_level(level_num)
	_write_or_defer_value(group_value)


static func reconcile_after_cloud_restore(level_num: int, local_tags: Dictionary) -> bool:
	if not ENABLED:
		return false
	var latest_group_value: String = normal_level_group_value_for_level(level_num)
	if latest_group_value.is_empty():
		push_warning(
			"[normal_level_group] invalid cloud-restored main level=%d, skip local tag" % level_num
		)
		return false
	if not should_update_normal_level_group_after_cloud_restore(level_num, local_tags):
		GameState.set_persisted_user_tag(LOCAL_TAG_KEY, latest_group_value)
		return false
	_write_or_defer_value(latest_group_value)
	return true


static func write_pending_update_after_sdk_initialized() -> bool:
	if not ENABLED:
		return false
	if _pending_group_value.is_empty():
		return false
	var group_value: String = _pending_group_value
	_pending_group_value = ""
	_write_value(group_value)
	print("[normal_level_group] write pending local tag after UserTag init: %s" % [group_value])
	return true


static func _ensure_usertag_init_binding() -> void:
	var callback: Callable = _on_usertag_ready
	if not UniKitManager.usertag_ready.is_connected(callback):
		UniKitManager.usertag_ready.connect(callback, CONNECT_ONE_SHOT)


static func _ensure_cloud_restore_binding() -> void:
	var callback: Callable = _on_cloud_progress_restored
	if not GameState.cloud_progress_restored.is_connected(callback):
		GameState.cloud_progress_restored.connect(callback)


static func _on_usertag_ready(_data: Dictionary) -> void:
	write_pending_update_after_sdk_initialized()
	if _pending_cloud_restore_check:
		_start_cloud_restore_check()


static func _on_cloud_progress_restored(_level_num: int) -> void:
	_cloud_restore_revision += 1
	_pending_cloud_restore_check = true
	if UniKitManager.is_usertag_inited():
		_start_cloud_restore_check()
	else:
		_ensure_usertag_init_binding()


static func _start_cloud_restore_check() -> void:
	if _cloud_restore_query_in_flight:
		return
	_pending_cloud_restore_check = false
	_cloud_restore_query_in_flight = true
	var request_revision: int = _cloud_restore_revision
	_query_and_reconcile_cloud_restore(request_revision)


static func _query_and_reconcile_cloud_restore(request_revision: int) -> void:
	var local_tags: Dictionary = await UniKitManager.get_local_tags()
	_cloud_restore_query_in_flight = false
	if request_revision != _cloud_restore_revision:
		_start_cloud_restore_check()
		return
	reconcile_after_cloud_restore(GameState.get_current_level(), local_tags)


static func _write(level_num: int) -> void:
	var group_value: String = normal_level_group_value_for_level(level_num)
	if group_value.is_empty():
		push_warning("[normal_level_group] invalid main level=%d, skip local tag" % level_num)
		return
	_write_or_defer_value(group_value)


static func _write_or_defer_value(group_value: String) -> void:
	if UniKitManager.is_usertag_inited():
		_write_value(group_value)
		return
	_pending_group_value = group_value
	_ensure_usertag_init_binding()


static func _write_value(group_value: String) -> void:
	UniKitManager.add_local_tag(LOCAL_TAG_KEY, group_value)
	GameState.set_persisted_user_tag(LOCAL_TAG_KEY, group_value)
	print("[normal_level_group] write local tag: %s" % [group_value])
