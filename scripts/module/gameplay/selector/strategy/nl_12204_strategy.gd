## 普通关卡策略 normal_level_12204：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12204Strategy
extends NL12100Strategy

const SUPER_HARD_RANK: int = 4

var _r4_bank_cache: Array = []


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12204"


func _super_hard_bank() -> Array:
	if not _r4_bank_cache.is_empty():
		return _r4_bank_cache
	var full_bank: Array = BankData.get_all_super_hard_levels()
	var combined: Array = []
	for level: Variant in full_bank:
		if int((level as Dictionary).get("r", 0)) == SUPER_HARD_RANK:
			combined.append(level)
	var extra_bank: Array = BankData.get_all_super_hard_r4_levels()
	combined.append_array(extra_bank)
	if combined.is_empty():
		push_error("[NL12204Strategy] 极难关 R%d 题池为空，回退整库" % SUPER_HARD_RANK)
		return full_bank
	if extra_bank.is_empty():
		push_error("[NL12204Strategy] bankDataSuperHardR4.json 为空或缺失")
	_r4_bank_cache = combined
	return _r4_bank_cache
