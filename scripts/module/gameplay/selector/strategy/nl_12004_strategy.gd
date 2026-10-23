## 普通关卡策略 normal_level_12004：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12004Strategy
extends NL11900Strategy

const MILESTONES: Array[int] = [
	40,
	67,
	100,
	111,
	140,
	150,
	190,
	222,
	300,
	333,
	400,
	500,
	555,
	600,
	700,
	777,
	900,
	1000,
	1100,
	1111,
	1500,
	2000,
	2026,
	2222,
	2500,
	3000,
	3333,
	4000,
	4444,
	5000,
]

var _special_delivery: bool = false


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12004"


func select(request: LevelSelectRequest) -> Dictionary:
	_special_delivery = false
	var level: int = request.level_num
	if MILESTONES.has(level):
		for source: Dictionary in BankData.get_digit_sp_levels():
			if str(source.get("pattern", "")) == str(level):
				var entry: Dictionary = source.duplicate(true)
				entry["_bank_source"] = "digit_sp"
				entry["_bank_idx"] = int(entry.get("id", 0))
				entry["_bank_tier"] = ""
				entry["_bank_rank"] = int(entry.get("r", 1))
				_special_delivery = true
				return _deliver_special(entry, level)
		return {"failed_reason": "missing_digit_sp_%d" % level}
	if level == 44 or level == 104:
		var old_level: int = level - 4
		var ctx: LevelSelectContext = LevelSelectContext.new()
		ctx.level_num = old_level
		_special_delivery = true
		return _deliver_special(SpecialProvider.new().next_entry(ctx), level)
	return super.select(request)


func on_delivery(entry: Dictionary) -> void:
	if _special_delivery:
		return
	super.on_delivery(entry)
