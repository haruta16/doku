## 实验配置 health_points_rule：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HealthPointsRuleConfig

const VALUE_CONTROL: String = "{1,end,3}"

const _END_LEVEL: int = 100000

const DEFAULT_LIVES: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "health_points_rule"
	default_value = VALUE_CONTROL


func get_rule_dsl() -> String:
	return str(value())


func lives_for_level(level_num: int, board_size: int) -> Dictionary:
	var intervals: Array = _parse_dsl(get_rule_dsl())
	if intervals.is_empty():
		return {"lives": DEFAULT_LIVES, "inf": false}
	for entry: Dictionary in intervals:
		if level_num >= entry.start and level_num < entry.end:
			if entry.is_inf:
				return {"lives": DEFAULT_LIVES, "inf": true}
			if entry.kind == "board":
				return {"lives": board_size, "inf": false}
			return {"lives": int(str(entry.kind)), "inf": false}

	return {"lives": DEFAULT_LIVES, "inf": false}


func _parse_dsl(dsl: String) -> Array:
	var trimmed: String = dsl.strip_edges()
	if trimmed.is_empty():
		return []
	var out: Array = []
	for seg: String in trimmed.split(",{"):
		var seg_text: String = seg.strip_edges()

		if not seg_text.begins_with("{"):
			seg_text = "{" + seg_text
		seg_text = seg_text.trim_prefix("{").trim_suffix("}")
		var parts: PackedStringArray = seg_text.split(",")
		if parts.size() != 3:
			push_error("HealthPointsRule: DSL 段 '%s' 不是 {起始关,结束关,命数} 三段" % seg_text)
			return []
		var start_num: int = _parse_level_token(parts[0])
		var end_num: int = _parse_level_token(parts[1])
		if start_num < 1 or end_num <= start_num:
			push_error("HealthPointsRule: DSL 段 '%s' 起始关/结束关非法(须 >=1 且 结束 > 起始)" % seg_text)
			return []
		var lives_token: String = parts[2].to_lower()
		var entry: Dictionary = {
			"start": start_num, "end": end_num, "kind": lives_token, "is_inf": false
		}
		if lives_token == "inf":
			entry.is_inf = true
		elif lives_token == "board":
			entry.kind = "board"
		elif lives_token.is_valid_int():
			var lives_num: int = int(lives_token)
			if lives_num < 1:
				push_error("HealthPointsRule: DSL 段 '%s' 命数 %d < 1" % [seg_text, lives_num])
				return []
		else:
			push_error(
				"HealthPointsRule: DSL 段 '%s' 命数 '%s' 非法(须正整数/inf/board)" % [seg_text, lives_token]
			)
			return []
		if not out.is_empty() and start_num < out[out.size() - 1].end:
			push_error("HealthPointsRule: DSL 段 '%s' 与上一区间重叠或乱序" % seg_text)
			return []
		out.append(entry)
	return out


func _parse_level_token(token: String) -> int:
	var token_text: String = token.strip_edges().to_lower()
	if token_text == "end":
		return _END_LEVEL
	if token_text.is_valid_int():
		return int(token_text)
	return -1
