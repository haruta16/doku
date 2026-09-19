# AB 分流调试页：查当前 AB 分组 id / 国家码，可手改后写进 SDK 并直接退出游戏（重启才生效）
# 只在非 rel 的构建里注册（UIRegistry._DEV_PAGES）；由作弊面板的 ab_debug 命令打开
class_name AbDebugPage
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _current_id_value: Label = $CenterPanel/Margin/VBox/CurrentIdRow/CurrentIdValue # 当前分组 id（只读）
@onready
var _current_country_value: Label = $CenterPanel/Margin/VBox/CurrentCountryRow/CurrentCountryValue # 当前国家码（只读）
@onready var _group_id_input: LineEdit = $CenterPanel/Margin/VBox/GroupIdInputRow/GroupIdInput # 手输分组 id
@onready var _country_input: LineEdit = $CenterPanel/Margin/VBox/CountryInputRow/CountryInput # 手输国家码（两位，自动转大写）


# 每次打开都刷新当前值并清空输入框（_params 未使用）
func on_show(_params: Dictionary = {}) -> void:
	_refresh_current_values()
	_group_id_input.text = ""
	_country_input.text = ""


# 从 ABTestManager 拉当前分组 id 与国家码，填进只读标签
func _refresh_current_values() -> void:
	_current_id_value.text = ABTestManager.get_ab_group_id()
	_current_country_value.text = ABTestManager.get_ab_country()


# IncrementBtn：把输入框里的数字加一；空的或非数字就按当前值起算
func _on_increment_pressed() -> void:
	var base_str: String = _group_id_input.text.strip_edges()
	if base_str.is_empty():
		base_str = _current_id_value.text.strip_edges()
	var base_int: int = 0
	if base_str.is_valid_int():
		base_int = base_str.to_int()
	_group_id_input.text = str(base_int + 1)


# RandomBtn：随机填一个 0~999 的分组 id
func _on_random_pressed() -> void:
	_group_id_input.text = str(randi() % 1000)


# ConfirmBtn：写回分组/国家，然后退出游戏（0.2 秒后 quit，让 SDK 落地）
func _on_confirm_pressed() -> void:
	var group_id_str: String = _group_id_input.text.strip_edges()
	var country_str: String = _country_input.text.strip_edges().to_upper()
	var changed_group: bool = false
	var changed_country: bool = false

	# 分组 id 必须是纯数字才写，否则保持原样
	if not group_id_str.is_empty() and group_id_str.is_valid_int():
		ABTestManager.set_ab_group_id(group_id_str)
		changed_group = true

	# 国家码必须恰好两位（已转大写）才写
	if country_str.length() == 2:
		ABTestManager.set_ab_country(country_str)
		changed_country = true

	# 打印实际生效情况：可能只改成功了其中一项
	print(
		(
			"[AbDebugPage] confirm group_id=%s(changed=%s) country=%s(changed=%s) → quit"
			% [group_id_str, changed_group, country_str, changed_country]
		)
	)

	UIManager.hide_ui(UiName.AB_DEBUG) # 先关掉本页，再退出进程

	await get_tree().create_timer(0.2).timeout # 等一下再退，避免页面还在关动画时就没了
	get_tree().quit() # 退出整个游戏


# CloseBtn：只关页面，不改任何设置
func _on_close_pressed() -> void:
	UIManager.hide_ui(UiName.AB_DEBUG)
