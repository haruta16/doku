class_name AbDebugPage
extends UIFrameWindow

@onready var _current_id_value: Label = $CenterPanel/Margin/VBox/CurrentIdRow/CurrentIdValue
@onready
var _current_country_value: Label = $CenterPanel/Margin/VBox/CurrentCountryRow/CurrentCountryValue
@onready var _group_id_input: LineEdit = $CenterPanel/Margin/VBox/GroupIdInputRow/GroupIdInput
@onready var _country_input: LineEdit = $CenterPanel/Margin/VBox/CountryInputRow/CountryInput


func on_show(_params: Dictionary = {}) -> void:
	_refresh_current_values()
	_group_id_input.text = ""
	_country_input.text = ""


func _refresh_current_values() -> void:
	_current_id_value.text = ABTestManager.get_ab_group_id()
	_current_country_value.text = ABTestManager.get_ab_country()


func _on_increment_pressed() -> void:
	var base_str: String = _group_id_input.text.strip_edges()
	if base_str.is_empty():
		base_str = _current_id_value.text.strip_edges()
	var base_int: int = 0
	if base_str.is_valid_int():
		base_int = base_str.to_int()
	_group_id_input.text = str(base_int + 1)


func _on_random_pressed() -> void:
	_group_id_input.text = str(randi() % 1000)


func _on_confirm_pressed() -> void:
	var group_id_str: String = _group_id_input.text.strip_edges()
	var country_str: String = _country_input.text.strip_edges().to_upper()
	var changed_group: bool = false
	var changed_country: bool = false

	if not group_id_str.is_empty() and group_id_str.is_valid_int():
		ABTestManager.set_ab_group_id(group_id_str)
		changed_group = true

	if country_str.length() == 2:
		ABTestManager.set_ab_country(country_str)
		changed_country = true

	print(
		(
			"[AbDebugPage] confirm group_id=%s(changed=%s) country=%s(changed=%s) → quit"
			% [group_id_str, changed_group, country_str, changed_country]
		)
	)

	UIManager.hide_ui(UiName.AB_DEBUG)

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _on_close_pressed() -> void:
	UIManager.hide_ui(UiName.AB_DEBUG)
