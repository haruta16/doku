## 打卡造数会话：检查当前界面是否允许修改，应用测试快照并刷新相关页面。
extends RefCounted

const FixtureData: GDScript = preload(
	"res://scripts/module/cheat/fixtures/streak_history_fixture_data.gd"
)

var _manager: Node
var _ui_manager: Node


func setup(manager: Node, ui_manager: Node) -> void:
	_manager = manager
	_ui_manager = ui_manager


func prepare(preset: String) -> Dictionary:
	if OS.has_feature("rel"):
		return _failure("发行包不提供打卡造数")
	var generated: Dictionary = FixtureData.build_preset(preset)
	if not generated["ok"]:
		return generated
	var reason: String = mutation_guard()
	if not reason.is_empty():
		return _failure(reason)
	if not _manager.cheat_apply_history_fixture(generated["data"], true):
		return _failure("造数保存失败，原内存和原文件保持不变")
	refresh_current_streak_pages()
	return _success("场景准备完成；进关通关后看对应表现，AB 保持当前设置", _summary())


## 区分状态查询、清历史、重载与造数；通过界面保护检查后才修改管理器和刷新页面。
func execute(arguments: Array[String]) -> Dictionary:
	if OS.has_feature("rel"):
		return _failure("发行包不提供历史造数")
	if arguments.is_empty():
		return _failure("请使用 streak_history help 查看语法")
	var operation: String = arguments[0]
	if operation in ["status", "clear", "reload"] and arguments.size() != 1:
		return _failure("%s 不接受额外参数" % operation)
	if operation == "status":
		return _success("当前状态", _summary())
	var generated: Dictionary
	if operation == "clear":
		var data: Dictionary = _manager.get_data().to_dict()
		data["history_ranges"] = []
		generated = {"ok": true, "data": data}
	elif operation != "reload":
		generated = FixtureData.build(arguments)
		if not generated["ok"]:
			return generated
	var reason: String = mutation_guard()
	if not reason.is_empty():
		return _failure(reason)
	if operation == "reload":
		if not _manager.cheat_reload_history_fixture():
			return _failure("加载失败；待决策 D 的冷启结算请使用隔离 runner")
		refresh_current_streak_pages()
		return _success("已按真实加载规则补种", _summary())
	if not _manager.cheat_apply_history_fixture(generated["data"], true):
		return _failure("造数保存失败，原内存和原文件保持不变")
	refresh_current_streak_pages()
	var message: String = (
		"历史已清空；保留 current，重新加载可能补种" if operation == "clear" else "造数完成；执行 streak 查看月历，通关走真实打卡"
	)
	return _success(message, _summary())


## 存在待开奖励、补签决策或尚未关闭的演出页面时拒绝造数，避免破坏进行中的结算。
func mutation_guard() -> String:
	if _manager.has_pending_show() or _manager.has_pending_revive_decision():
		return "请先完成本次打卡或补签表现，再准备场景"
	var windows: Array[Dictionary] = _capture_windows()
	for entry: Dictionary in windows:
		if not entry["showing"]:
			return "页面正在关闭，请等页面稳定后再操作"
		if (
			entry["name"] in [UiName.AWARD, UiName.STREAK_BACKFILL, UiName.DAILY_STREAK_SUCCESS]
			or (entry["name"] == UiName.STREAK and int(entry["params"].get("state", 0)) != 0)
		):
			return "请先关闭打卡成功页或领奖页，再准备场景"
	return ""


func refresh_current_streak_pages() -> void:
	var windows: Array[Dictionary] = _capture_windows()
	for entry: Dictionary in windows:
		if entry["name"] in [UiName.STREAK_HOME, UiName.STREAK]:
			_ui_manager.show_ui(entry["name"], entry["params"])


func _capture_windows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stacks: Dictionary = _ui_manager.get("_stacks")
	var layers: Array = stacks.keys()
	layers.sort()
	for layer: int in layers:
		var windows: Array = stacks[layer]
		for window: Control in windows:
			var params: Dictionary = {}
			var properties: Array[Dictionary] = window.get_property_list()
			for property: Dictionary in properties:
				if property["name"] == "last_params":
					params = window.get("last_params").duplicate(true)
				elif property["name"] == "_state":
					params["state"] = window.get("_state")
				elif property["name"] == "show_extended_reward_track":
					params["show_extended_reward_track"] = window.get("show_extended_reward_track")
			result.append(
				{
					"name": StringName(window.get_ui_name()),
					"params": params,
					"showing": window.is_showing()
				}
			)
	return result


func _summary() -> Dictionary:
	var data: Dictionary = _manager.get_data().to_dict()
	var result: Dictionary = FixtureData.summary(data, _manager.cheat_history_today())
	result["display_current"] = _manager.get_display_streak()
	result["display_cycle"] = _manager.get_display_reward_cycle()
	result["pending_uid"] = _manager.get_pending_show_uid()
	var disk: ConfigFile = (
		SaveStore.plain_file("user://streak.cfg").load_config()
		if FileAccess.file_exists("user://streak.cfg")
		else null
	)
	result["history_on_disk"] = disk != null and disk.has_section_key("streak", "history_ranges")
	return result


func _success(message: String, summary: Dictionary) -> Dictionary:
	return {"ok": true, "message": message, "summary": summary}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
