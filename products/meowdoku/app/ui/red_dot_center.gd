## 红点规则中心：注册条件与消费回调，汇总音乐、反馈等入口的提示状态。
extends Node

signal count_changed(dot_id: String, count: int)

var _counts: Dictionary = {}

var _rules: Dictionary = {}


func _ready() -> void:
	_register_rules()

	ABTestManager.values_reloaded.connect(_on_ab_values_reloaded)

	refresh_all()


func _register_rules() -> void:
	_register(
		DotName.MUSIC_ENTRY, [ABTestManager.bgm_test.key], _cond_music_entry, _consume_music_entry
	)

	_register(DotName.MUSIC_SWITCH, [ABTestManager.bgm_test.key], _cond_music_switch)

	_register(DotName.HELPSHIFT_UNREAD, [], _cond_helpshift_unread)
	_register(
		DotName.PATTERN_ENTRY,
		[ABTestManager.blind_mod_entry.key],
		_cond_pattern_entry,
		_consume_pattern_entry
	)
	_register(
		DotName.PATTERN_SWITCH,
		[ABTestManager.blind_mod_entry.key],
		_cond_pattern_switch,
		_consume_pattern_switch
	)


func _register(
	dot_id: StringName, ab_keys: Array, cond: Callable, consume: Callable = Callable()
) -> void:
	_rules[dot_id] = {"ab_keys": ab_keys, "cond": cond, "consume": consume}


func _cond_music_entry() -> bool:
	if ABTestManager == null or ABTestManager.bgm_test == null:
		return false
	return (
		ABTestManager.bgm_test.has_music_switch() and not GameState.is_music_entry_dot_dismissed()
	)


func _consume_music_entry() -> void:
	GameState.mark_music_entry_dot_dismissed()


func _cond_music_switch() -> bool:
	if ABTestManager == null or ABTestManager.bgm_test == null:
		return false
	return ABTestManager.bgm_test.has_music_switch() and not GameState.is_music_user_modified()


func _cond_helpshift_unread() -> bool:
	return HelpshiftManager.get_unread_count() > 0


func _cond_pattern_entry() -> bool:
	if ABTestManager == null or ABTestManager.blind_mod_entry == null:
		return false
	return GameState.is_tutorial_done() and not GameState.is_pattern_entry_dot_dismissed()


func _consume_pattern_entry() -> void:
	GameState.mark_pattern_entry_dot_dismissed()


func _cond_pattern_switch() -> bool:
	if ABTestManager == null or ABTestManager.blind_mod_entry == null:
		return false
	return GameState.is_tutorial_done() and not GameState.is_pattern_switch_dot_dismissed()


func _consume_pattern_switch() -> void:
	GameState.mark_pattern_switch_dot_dismissed()


func refresh(dot_id: StringName) -> void:
	var rule: Dictionary = _rules.get(dot_id, {})
	if rule.is_empty():
		push_error("RedDotCenter.refresh: 未登记的规则型 dot_id '%s'" % dot_id)
		return
	_set_count(dot_id, 1 if (rule["cond"] as Callable).call() else 0)


func refresh_all() -> void:
	for dot_id: StringName in _rules:
		refresh(dot_id)


func dismiss(dot_id: StringName) -> void:
	var rule: Dictionary = _rules.get(dot_id, {})
	if rule.is_empty():
		push_error("RedDotCenter.dismiss: 未登记的规则型 dot_id '%s'" % dot_id)
		return
	var consume: Callable = rule["consume"] as Callable
	if not consume.is_valid():
		push_error(
			"RedDotCenter.dismiss: dot '%s' 是被动消耗型(未登记 consume),持久标志由别的业务动作写,应改调 refresh()" % dot_id
		)
		return
	if (rule["cond"] as Callable).call():
		consume.call()
	refresh(dot_id)


func is_on(dot_id: StringName) -> bool:
	return get_count(dot_id) > 0


func get_count(dot_id: String) -> int:
	return _counts.get(dot_id, 0)


func _set_count(dot_id: String, count: int) -> void:
	if dot_id == "":
		return
	if _counts.get(dot_id, 0) == count:
		return
	_counts[dot_id] = count
	count_changed.emit(dot_id, count)


func _on_ab_values_reloaded(_timing: String, keys: Array[String]) -> void:
	for dot_id: StringName in _rules:
		for k: String in (_rules[dot_id] as Dictionary)["ab_keys"] as Array:
			if k in keys:
				refresh(dot_id)
				break
