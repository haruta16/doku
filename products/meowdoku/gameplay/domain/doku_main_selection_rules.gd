## 主线选题的纯规则；运行时抽样与内容发布检查共享同一组可达选择。
## 不访问玩家存档、活动内容或 AB 单例，也不推进题库游标。
class_name DokuMainSelectionRules
extends RefCounted

# 201 关以后难度分段不再变化；分段内仅依赖关卡尾数（周期 10）。
const STAGE_STARTS: Array[int] = [1, 6, 21, 51, 101, 201]
# base/j 是 LevelData 无尺寸覆盖入口；2..8 是 GamePage 当前客户端的尺寸 AB 覆盖。
const SIZE_GROUPS: Array[String] = ["base", "j", "2", "3", "4", "5", "6", "7", "8"]
const RULE_GROUPS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]


static func is_hard(level: int, group: int) -> bool:
	if group == 10:
		return level >= 29 and level % 10 == 9
	return level >= 21 and level % 10 == 0


static func normal_strategy(level: int, current: int) -> int:
	if level <= 5:
		return 1
	return maxi(2, current) if level >= 51 else current


static func rank_for(strategy: int) -> int:
	return {5: 4, 6: 5, 7: 5}.get(strategy, strategy)


static func tier_for(strategy: int) -> String:
	return "H" if strategy in [5, 7] else "N"


## recipe 描述一个固定档位或闭区间；随机只发生在运行时 select 中。
## tracked_max_strategy 是 G 组本次跟踪的原始顶档，-1 表示不更新连续顶档标志。
static func _recipe(level: int, group: int, current: int, previous_was_max: bool) -> Dictionary:
	if is_hard(level, group):
		var rank: int = 5
		var tier: String = "N"
		var coin: bool = false
		if group == 9:
			rank = 4
		elif group == 10:
			if level < 51 or (level < 101 and current < 4):
				rank = 4
			elif level >= 201 and current >= 6:
				tier = "H"
		elif group not in [4, 5, 8] and level >= 201 and current >= 6:
			tier = "H"
			coin = group == 11
		return {"hard": true, "rank": rank, "tier": tier, "coin": coin}
	var strategy: int = normal_strategy(level, current)
	if group in [6, 7] and level >= 51 and level % 10 == 1:
		return {"hard": false, "low": 2, "high": 3 if level >= 101 else 2, "random": level >= 101, "mod1": true, "tracked_max_strategy": -1}
	var cap: int = 2
	if level >= 201:
		cap = 6
	elif level >= 101:
		cap = 5
	elif level >= 51:
		cap = 4
	elif level >= 21:
		cap = 3
	if group in [1, 8]:
		cap = mini(cap, 4)
	elif group in [4, 5]:
		cap = mini(cap, 5)
	elif group == 9:
		cap = mini(cap, 3)
	strategy = mini(strategy, cap)
	var low: int = strategy
	var high: int = strategy
	var random: bool = false
	var tracked_max_strategy: int = -1
	if group == 4:
		low = 2 if level >= 51 else 1
		random = true
	elif group == 5 and level >= 101:
		low = 2
		random = true
	elif strategy >= 3 and group in [2, 3, 6, 7, 8, 9, 10, 11]:
		low = maxi(2, strategy - 1) if group == 3 else 2
		random = true
		if group == 7:
			tracked_max_strategy = strategy
			if level > 50 and previous_was_max:
				high = maxi(2, high - 1)
	return {"hard": false, "low": low, "high": high, "random": random, "mod1": false, "tracked_max_strategy": tracked_max_strategy}


static func _normal_choice(recipe: Dictionary, strategy: int, daily_easy: bool) -> Dictionary:
	# 按抽样时的档位判定是否命中原始顶档，随后每日降档不改变该历史事实。
	var next_previous_was_max: Variant = null if int(recipe.tracked_max_strategy) < 0 else strategy == int(recipe.tracked_max_strategy)
	var consume: bool = daily_easy and strategy > 1
	if consume:
		strategy -= 1
	return {"rank": rank_for(strategy), "tier": tier_for(strategy), "hard": false,
		"consume_daily": consume, "mod1": recipe.mod1, "next_previous_was_max": next_previous_was_max}


## previous_was_max 是已有历史；返回的 next_previous_was_max 为 null 时保留它，否则写入新布尔值。
static func select(level: int, group: int, current: int, daily_easy: bool, previous_was_max: bool, rng: RandomNumberGenerator) -> Dictionary:
	var recipe := _recipe(level, group, current, previous_was_max)
	if recipe.hard:
		var tier: String = recipe.tier
		if recipe.coin and rng.randi() % 2 == 0:
			tier = "N"
		return {"rank": recipe.rank, "tier": tier, "hard": true, "consume_daily": false, "mod1": false, "next_previous_was_max": null}
	var strategy: int = rng.randi_range(recipe.low, recipe.high) if recipe.random else int(recipe.low)
	return _normal_choice(recipe, strategy, daily_easy)


## 枚举同一 recipe 的全部结果，包含每日首局降档及 G 组连续顶档限制。
static func possibilities(level: int, group: int) -> Array[Dictionary]:
	var found: Dictionary = {}
	# 现行 DDA（MeowdokuSettlementRules）策略上限为 6；7 仅保留旧映射兼容。
	for current: int in range(1, 7):
		for previous: bool in [false, true]:
			var recipe := _recipe(level, group, current, previous)
			if recipe.hard:
				for tier: String in (["N", "H"] if recipe.coin else [recipe.tier]):
					found["%d/%s" % [recipe.rank, tier]] = {"rank": recipe.rank, "tier": tier, "hard": true}
				continue
			for strategy: int in range(int(recipe.low), int(recipe.high) + 1):
				for daily: bool in [false, true]:
					var choice := _normal_choice(recipe, strategy, daily)
					found["%d/%s" % [choice.rank, choice.tier]] = choice
	var result: Array[Dictionary] = []
	result.assign(found.values())
	return result


## 保留消费者的联合 tier 回退和题源准入顺序。LK 改造题只用一次，不属于可循环兜底池。
static func cycling_pools(size: int, rank: int, tier: String, main: bool, regular: Array, style: Array, gc: Array) -> Dictionary:
	var selected_regular: Array = _tier(regular, tier)
	var selected_style: Array = _tier(style, tier)
	if not tier.is_empty() and selected_regular.is_empty() and selected_style.is_empty():
		selected_regular = regular
		selected_style = style
	if main and size == 10 and rank in [3, 4]:
		selected_regular = []
	var selected_gc: Array = []
	if (size == 10 and rank == 1) or size == 11:
		selected_gc = _tier(gc, tier)
		if not tier.is_empty() and selected_gc.is_empty():
			selected_gc = gc
	return {"regular": selected_regular, "lkstyle": selected_style, "gc": selected_gc}


static func normal_tier(tier: String, regular: Array, style: Array) -> String:
	return "" if tier == "N" and _tier(regular, tier).is_empty() and _tier(style, tier).is_empty() else tier


static func _tier(entries: Array, tier: String) -> Array:
	return entries if tier.is_empty() else entries.filter(func(entry: Dictionary) -> bool: return entry.get("tier", "") == tier)
