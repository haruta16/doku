## 普通关卡策略 LevelSelectionStrategyResolver：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name LevelSelectionStrategyResolver
extends RefCounted

const CONTROL_ID: StringName = &"normal_level_0"
var _cache: Dictionary = {}

const _VALUE_TO_ID: Dictionary = {
	0: &"normal_level_0",
	11310: &"normal_level_11310",
	11501: &"normal_level_11501",
	11502: &"normal_level_11502",
	11503: &"normal_level_11503",
	11504: &"normal_level_11504",
	11505: CONTROL_ID,
	11506: CONTROL_ID,
	11507: CONTROL_ID,
	11508: CONTROL_ID,
	11509: &"normal_level_11509",
	11510: &"normal_level_11510",
	11511: &"normal_level_11511",
	11512: &"normal_level_11512",
	11513: &"normal_level_11513",
	11514: &"normal_level_11514",
	11515: &"normal_level_11515",
	11701: &"normal_level_11701",
	11702: &"normal_level_11702",
	11703: &"normal_level_11703",
	11704: &"normal_level_11704",
	11705: &"normal_level_11705",
	11706: &"normal_level_11706",
	11707: &"normal_level_11707",
	11708: &"normal_level_11708",
	11709: &"normal_level_11709",
	11710: &"normal_level_11710",
	11711: &"normal_level_11711",
	11923: &"normal_level_11923",
	11924: &"normal_level_11924",
	11925: &"normal_level_11925",
	11801: &"normal_level_11801",
	11802: &"normal_level_11802",
	11803: &"normal_level_11803",
	11804: &"normal_level_11804",
	11805: &"normal_level_11805",
	11806: &"normal_level_11806",
	11807: &"normal_level_11807",
	11919: &"normal_level_11919",
	11920: &"normal_level_11920",
	11808: &"normal_level_11502",
	11809: &"normal_level_11502",
	11904: &"normal_level_11904",
	11905: &"normal_level_11905",
	11906: &"normal_level_11906",
	11907: &"normal_level_11907",
	11908: &"normal_level_11908",
	11909: &"normal_level_11909",
	11910: &"normal_level_11910",
	11911: &"normal_level_11911",
	11913: &"normal_level_11913",
	11914: &"normal_level_11914",
	11915: &"normal_level_11915",
	11912: &"normal_level_11912",
	11916: &"normal_level_11916",
	11917: &"normal_level_11917",
	11918: &"normal_level_11918",
	11901: &"normal_level_11901",
	11902: &"normal_level_11902",
	11903: &"normal_level_11903",
	11900: &"normal_level_11900",
	12001: &"normal_level_12001",
	12002: &"normal_level_12002",
	12004: &"normal_level_12004",
	12005: &"normal_level_12005",
	12006: &"normal_level_12006",
	12007: &"normal_level_12007",
	12008: &"normal_level_12008",
	12009: &"normal_level_12009",
	11921: &"normal_level_11921",
	11922: &"normal_level_11922",
	12100: &"normal_level_12100",
	12207: &"normal_level_12207",
	12208: &"normal_level_12208",
	12210: &"normal_level_12210",
	12101: &"normal_level_12101",
	12102: &"normal_level_12102",
	12103: &"normal_level_12103",
	12104: &"normal_level_12104",
	12105: &"normal_level_12105",
	12106: &"normal_level_12106",
	12107: &"normal_level_12107",
	12108: &"normal_level_12108",
	12201: &"normal_level_12201",
	12202: &"normal_level_12202",
	12203: &"normal_level_12203",
	12204: &"normal_level_12204",
	12205: &"normal_level_12205",
	12206: &"normal_level_12206",
	12209: &"normal_level_12209",
	11951: &"normal_level_11951",
	11952: &"normal_level_11952",
	11953: &"normal_level_11953",
	11954: &"normal_level_11954",
	11955: &"normal_level_11955",
	11956: &"normal_level_11956",
	11957: &"normal_level_11957",
	11958: &"normal_level_11958",
	11959: &"normal_level_11959",
	11960: &"normal_level_11960",
	11961: &"normal_level_11961",
	11962: &"normal_level_11962",
	11963: &"normal_level_11963",
	11964: &"normal_level_11964",
	11965: &"normal_level_11965",
	11966: &"normal_level_11966",
	11967: &"normal_level_11967",
	11968: &"normal_level_11968",
	11969: &"normal_level_11969",
	11970: &"normal_level_11970",
	11971: &"normal_level_11971",
	11972: &"normal_level_11972",
}


func resolve_by_value(normal_level_value: int) -> LevelSelectionStrategy:
	var strategy_id: StringName = _VALUE_TO_ID.get(normal_level_value, StringName())
	if strategy_id.is_empty():
		var msg: String = (
			"LevelSelectionStrategyResolver: unknown normal_level=%d, fallback=%s"
			% [normal_level_value, CONTROL_ID]
		)

		if OS.has_feature("rel") or OS.has_feature("pre"):
			push_error(msg)
		else:
			push_warning(msg)
		strategy_id = CONTROL_ID
	return _get_or_create(strategy_id)


func resolve_by_id(strategy_id: StringName) -> LevelSelectionStrategy:
	if not _VALUE_TO_ID.values().has(strategy_id):
		push_error(
			(
				"LevelSelectionStrategyResolver: unknown strategy_id=%s, fallback=%s"
				% [strategy_id, CONTROL_ID]
			)
		)
		return _get_or_create(CONTROL_ID)
	return _get_or_create(strategy_id)


func _get_or_create(strategy_id: StringName) -> LevelSelectionStrategy:
	if not _cache.has(strategy_id):
		var strategy: LevelSelectionStrategy = _create(strategy_id)
		if strategy == null:
			return null
		_cache[strategy_id] = strategy
	return _cache[strategy_id] as LevelSelectionStrategy


const _STRATEGY_PATHS: Dictionary = {
	&"normal_level_0": "res://scripts/module/gameplay/selector/strategy/nl_control_strategy.gd",
	&"normal_level_11310": "res://scripts/module/gameplay/selector/strategy/nl_11310_strategy.gd",
	&"normal_level_11501": "res://scripts/module/gameplay/selector/strategy/nl_11501_strategy.gd",
	&"normal_level_11502": "res://scripts/module/gameplay/selector/strategy/nl_11502_strategy.gd",
	&"normal_level_11503": "res://scripts/module/gameplay/selector/strategy/nl_11503_strategy.gd",
	&"normal_level_11504": "res://scripts/module/gameplay/selector/strategy/nl_11504_strategy.gd",
	&"normal_level_11509": "res://scripts/module/gameplay/selector/strategy/nl_11509_strategy.gd",
	&"normal_level_11510": "res://scripts/module/gameplay/selector/strategy/nl_11510_strategy.gd",
	&"normal_level_11511": "res://scripts/module/gameplay/selector/strategy/nl_11511_strategy.gd",
	&"normal_level_11512": "res://scripts/module/gameplay/selector/strategy/nl_11512_strategy.gd",
	&"normal_level_11513": "res://scripts/module/gameplay/selector/strategy/nl_11513_strategy.gd",
	&"normal_level_11514": "res://scripts/module/gameplay/selector/strategy/nl_11514_strategy.gd",
	&"normal_level_11515": "res://scripts/module/gameplay/selector/strategy/nl_11515_strategy.gd",
	&"normal_level_11701": "res://scripts/module/gameplay/selector/strategy/nl_11701_strategy.gd",
	&"normal_level_11702": "res://scripts/module/gameplay/selector/strategy/nl_11702_strategy.gd",
	&"normal_level_11703": "res://scripts/module/gameplay/selector/strategy/nl_11703_strategy.gd",
	&"normal_level_11704": "res://scripts/module/gameplay/selector/strategy/nl_11704_strategy.gd",
	&"normal_level_11705": "res://scripts/module/gameplay/selector/strategy/nl_11705_strategy.gd",
	&"normal_level_11706": "res://scripts/module/gameplay/selector/strategy/nl_11706_strategy.gd",
	&"normal_level_11707": "res://scripts/module/gameplay/selector/strategy/nl_11707_strategy.gd",
	&"normal_level_11708": "res://scripts/module/gameplay/selector/strategy/nl_11708_strategy.gd",
	&"normal_level_11709": "res://scripts/module/gameplay/selector/strategy/nl_11709_strategy.gd",
	&"normal_level_11710": "res://scripts/module/gameplay/selector/strategy/nl_11710_strategy.gd",
	&"normal_level_11711": "res://scripts/module/gameplay/selector/strategy/nl_11711_strategy.gd",
	&"normal_level_11923": "res://scripts/module/gameplay/selector/strategy/nl_11923_strategy.gd",
	&"normal_level_11924": "res://scripts/module/gameplay/selector/strategy/nl_11924_strategy.gd",
	&"normal_level_11925": "res://scripts/module/gameplay/selector/strategy/nl_11925_strategy.gd",
	&"normal_level_11801": "res://scripts/module/gameplay/selector/strategy/nl_11801_strategy.gd",
	&"normal_level_11802": "res://scripts/module/gameplay/selector/strategy/nl_11802_strategy.gd",
	&"normal_level_11803": "res://scripts/module/gameplay/selector/strategy/nl_11803_strategy.gd",
	&"normal_level_11804": "res://scripts/module/gameplay/selector/strategy/nl_11804_strategy.gd",
	&"normal_level_11805": "res://scripts/module/gameplay/selector/strategy/nl_11805_strategy.gd",
	&"normal_level_11806": "res://scripts/module/gameplay/selector/strategy/nl_11806_strategy.gd",
	&"normal_level_11807": "res://scripts/module/gameplay/selector/strategy/nl_11807_strategy.gd",
	&"normal_level_11919": "res://scripts/module/gameplay/selector/strategy/nl_11919_strategy.gd",
	&"normal_level_11920": "res://scripts/module/gameplay/selector/strategy/nl_11920_strategy.gd",
	&"normal_level_11904": "res://scripts/module/gameplay/selector/strategy/nl_11904_strategy.gd",
	&"normal_level_11905": "res://scripts/module/gameplay/selector/strategy/nl_11905_strategy.gd",
	&"normal_level_11906": "res://scripts/module/gameplay/selector/strategy/nl_11906_strategy.gd",
	&"normal_level_11907": "res://scripts/module/gameplay/selector/strategy/nl_11907_strategy.gd",
	&"normal_level_11908": "res://scripts/module/gameplay/selector/strategy/nl_11908_strategy.gd",
	&"normal_level_11909": "res://scripts/module/gameplay/selector/strategy/nl_11909_strategy.gd",
	&"normal_level_11910": "res://scripts/module/gameplay/selector/strategy/nl_11910_strategy.gd",
	&"normal_level_11911": "res://scripts/module/gameplay/selector/strategy/nl_11911_strategy.gd",
	&"normal_level_11912": "res://scripts/module/gameplay/selector/strategy/nl_11912_strategy.gd",
	&"normal_level_11913": "res://scripts/module/gameplay/selector/strategy/nl_11913_strategy.gd",
	&"normal_level_11914": "res://scripts/module/gameplay/selector/strategy/nl_11914_strategy.gd",
	&"normal_level_11915": "res://scripts/module/gameplay/selector/strategy/nl_11915_strategy.gd",
	&"normal_level_11916": "res://scripts/module/gameplay/selector/strategy/nl_11916_strategy.gd",
	&"normal_level_11917": "res://scripts/module/gameplay/selector/strategy/nl_11917_strategy.gd",
	&"normal_level_11918": "res://scripts/module/gameplay/selector/strategy/nl_11918_strategy.gd",
	&"normal_level_11901": "res://scripts/module/gameplay/selector/strategy/nl_11901_strategy.gd",
	&"normal_level_11902": "res://scripts/module/gameplay/selector/strategy/nl_11902_strategy.gd",
	&"normal_level_11903": "res://scripts/module/gameplay/selector/strategy/nl_11903_strategy.gd",
	&"normal_level_11900": "res://scripts/module/gameplay/selector/strategy/nl_11900_strategy.gd",
	&"normal_level_12004": "res://scripts/module/gameplay/selector/strategy/nl_12004_strategy.gd",
	&"normal_level_12001": "res://scripts/module/gameplay/selector/strategy/nl_12001_strategy.gd",
	&"normal_level_12002": "res://scripts/module/gameplay/selector/strategy/nl_12002_strategy.gd",
	&"normal_level_12005": "res://scripts/module/gameplay/selector/strategy/nl_12005_strategy.gd",
	&"normal_level_12006": "res://scripts/module/gameplay/selector/strategy/nl_12006_strategy.gd",
	&"normal_level_12007": "res://scripts/module/gameplay/selector/strategy/nl_12007_strategy.gd",
	&"normal_level_12008": "res://scripts/module/gameplay/selector/strategy/nl_12008_strategy.gd",
	&"normal_level_12009": "res://scripts/module/gameplay/selector/strategy/nl_12009_strategy.gd",
	&"normal_level_12100": "res://scripts/module/gameplay/selector/strategy/nl_12100_strategy.gd",
	&"normal_level_12207": "res://scripts/module/gameplay/selector/strategy/nl_12207_strategy.gd",
	&"normal_level_12208": "res://scripts/module/gameplay/selector/strategy/nl_12208_strategy.gd",
	&"normal_level_12210": "res://scripts/module/gameplay/selector/strategy/nl_12210_strategy.gd",
	&"normal_level_12101": "res://scripts/module/gameplay/selector/strategy/nl_12101_strategy.gd",
	&"normal_level_12102": "res://scripts/module/gameplay/selector/strategy/nl_12102_strategy.gd",
	&"normal_level_12103": "res://scripts/module/gameplay/selector/strategy/nl_12103_strategy.gd",
	&"normal_level_12104": "res://scripts/module/gameplay/selector/strategy/nl_12104_strategy.gd",
	&"normal_level_12105": "res://scripts/module/gameplay/selector/strategy/nl_12105_strategy.gd",
	&"normal_level_12106": "res://scripts/module/gameplay/selector/strategy/nl_12106_strategy.gd",
	&"normal_level_12107": "res://scripts/module/gameplay/selector/strategy/nl_12107_strategy.gd",
	&"normal_level_12108": "res://scripts/module/gameplay/selector/strategy/nl_12108_strategy.gd",
	&"normal_level_12201": "res://scripts/module/gameplay/selector/strategy/nl_12201_strategy.gd",
	&"normal_level_12202": "res://scripts/module/gameplay/selector/strategy/nl_12202_strategy.gd",
	&"normal_level_12203": "res://scripts/module/gameplay/selector/strategy/nl_12203_strategy.gd",
	&"normal_level_12204": "res://scripts/module/gameplay/selector/strategy/nl_12204_strategy.gd",
	&"normal_level_12205": "res://scripts/module/gameplay/selector/strategy/nl_12205_strategy.gd",
	&"normal_level_12206": "res://scripts/module/gameplay/selector/strategy/nl_12206_strategy.gd",
	&"normal_level_12209": "res://scripts/module/gameplay/selector/strategy/nl_12209_strategy.gd",
	&"normal_level_11921": "res://scripts/module/gameplay/selector/strategy/nl_11921_strategy.gd",
	&"normal_level_11922": "res://scripts/module/gameplay/selector/strategy/nl_11922_strategy.gd",
	&"normal_level_11951": "res://scripts/module/gameplay/selector/strategy/nl_11951_strategy.gd",
	&"normal_level_11952": "res://scripts/module/gameplay/selector/strategy/nl_11952_strategy.gd",
	&"normal_level_11953": "res://scripts/module/gameplay/selector/strategy/nl_11953_strategy.gd",
	&"normal_level_11954": "res://scripts/module/gameplay/selector/strategy/nl_11954_strategy.gd",
	&"normal_level_11955": "res://scripts/module/gameplay/selector/strategy/nl_11955_strategy.gd",
	&"normal_level_11956": "res://scripts/module/gameplay/selector/strategy/nl_11956_strategy.gd",
	&"normal_level_11957": "res://scripts/module/gameplay/selector/strategy/nl_11957_strategy.gd",
	&"normal_level_11958": "res://scripts/module/gameplay/selector/strategy/nl_11958_strategy.gd",
	&"normal_level_11959": "res://scripts/module/gameplay/selector/strategy/nl_11959_strategy.gd",
	&"normal_level_11960": "res://scripts/module/gameplay/selector/strategy/nl_11960_strategy.gd",
	&"normal_level_11961": "res://scripts/module/gameplay/selector/strategy/nl_11961_strategy.gd",
	&"normal_level_11962": "res://scripts/module/gameplay/selector/strategy/nl_11962_strategy.gd",
	&"normal_level_11963": "res://scripts/module/gameplay/selector/strategy/nl_11963_strategy.gd",
	&"normal_level_11964": "res://scripts/module/gameplay/selector/strategy/nl_11964_strategy.gd",
	&"normal_level_11965": "res://scripts/module/gameplay/selector/strategy/nl_11965_strategy.gd",
	&"normal_level_11966": "res://scripts/module/gameplay/selector/strategy/nl_11966_strategy.gd",
	&"normal_level_11967": "res://scripts/module/gameplay/selector/strategy/nl_11967_strategy.gd",
	&"normal_level_11968": "res://scripts/module/gameplay/selector/strategy/nl_11968_strategy.gd",
	&"normal_level_11969": "res://scripts/module/gameplay/selector/strategy/nl_11969_strategy.gd",
	&"normal_level_11970": "res://scripts/module/gameplay/selector/strategy/nl_11970_strategy.gd",
	&"normal_level_11971": "res://scripts/module/gameplay/selector/strategy/nl_11971_strategy.gd",
	&"normal_level_11972": "res://scripts/module/gameplay/selector/strategy/nl_11972_strategy.gd",
}


static func _create(strategy_id: StringName) -> LevelSelectionStrategy:
	var script_path: String = _STRATEGY_PATHS.get(strategy_id, _STRATEGY_PATHS[CONTROL_ID])
	var strategy_script: GDScript = load(script_path) as GDScript
	if strategy_script == null or not strategy_script.can_instantiate():
		push_error(
			(
				"LevelSelectionStrategyResolver: 无法加载策略脚本，strategy_id=%s path=%s"
				% [strategy_id, script_path]
			)
		)
		return null
	var strategy: LevelSelectionStrategy = strategy_script.new() as LevelSelectionStrategy
	if strategy == null:
		push_error(
			(
				"LevelSelectionStrategyResolver: 策略未实现基础接口，strategy_id=%s path=%s"
				% [strategy_id, script_path]
			)
		)
	return strategy
