## 陪伴猫策略工厂与默认接口：把实验组映射为业务模式，由子类声明外观、喂食和货币能力。
extends RefCounted
class_name HomeCompanionCatStrategy

const System: GDScript = preload("res://scripts/module/home/core/home_companion_system.gd")


static func create() -> HomeCompanionCatStrategy:
	return for_group(ABTestManager.home_companion_cat.value())


static func for_group(group: int) -> HomeCompanionCatStrategy:
	match group:
		HomeCompanionCatConfig.VALUE_HALLOWEEN_REWARDS:
			return for_mode(System.Mode.HALLOWEEN_REWARDS)
		HomeCompanionCatConfig.VALUE_CANNED_FOOD:
			return for_mode(System.Mode.DAILY_CANS)
		HomeCompanionCatConfig.VALUE_HALLOWEEN_COSMETIC:
			return for_mode(System.Mode.HALLOWEEN_COSMETIC)
		HomeCompanionCatConfig.VALUE_SATIETY:
			return for_mode(System.Mode.SATIETY)
		_:
			return HomeCompanionCatStrategy.new()


static func for_mode(mode: int) -> HomeCompanionCatStrategy:
	var implementation: GDScript
	match mode:
		System.Mode.HALLOWEEN_REWARDS:
			implementation = load(
				"res://scripts/module/abtest/strategy/home_companion_cat/home_companion_cat_strategy_rewards.gd"
			)
		System.Mode.DAILY_CANS:
			implementation = load(
				"res://scripts/module/abtest/strategy/home_companion_cat/home_companion_cat_strategy_cans.gd"
			)
		System.Mode.HALLOWEEN_COSMETIC:
			implementation = load(
				"res://scripts/module/abtest/strategy/home_companion_cat/home_companion_cat_strategy_cosmetic.gd"
			)
		System.Mode.SATIETY:
			implementation = load(
				"res://scripts/module/abtest/strategy/home_companion_cat/home_companion_cat_strategy_satiety.gd"
			)
		System.Mode.DAILY_INTERACT:
			implementation = load(
				"res://scripts/module/abtest/strategy/home_companion_cat/home_companion_cat_strategy_interact.gd"
			)
		_:
			return HomeCompanionCatStrategy.new()
	if implementation == null:
		push_error("Home companion strategy could not be loaded for mode %s" % mode)
		return HomeCompanionCatStrategy.new()
	return implementation.new() as HomeCompanionCatStrategy


func business_mode() -> int:
	return System.Mode.CONTROL


func has_companion() -> bool:
	return false


func halloween_skin() -> bool:
	return false


func allows_feeding() -> bool:
	return false


func earned_currency() -> StringName:
	return &""


func has_satiety() -> bool:
	return false


func tutorial_kind() -> StringName:
	return &""
