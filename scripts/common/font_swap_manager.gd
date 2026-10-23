## 全局字体切换：根据语言与实验组修改共享 FontVariation，并补齐跨语言回退字体。
extends RefCounted
class_name FontSwapManager

const _EN_ROBOTO: FontFile = preload("res://assets/fonts/Roboto.ttf")
const _EN_BALOO2: FontFile = preload("res://assets/fonts/candidates/Baloo2.ttf")
const _EN_ALIMAMA: FontFile = preload("res://assets/fonts/candidates/AliMama.ttf")
const _EN_GEOM: FontFile = preload("res://assets/fonts/candidates/GeomEN.ttf")

const _NOTO_FALLBACK: FontFile = preload("res://assets/fonts/NotoSourceHan-subset.ttf")

const _EN_FALLBACK: FontFile = preload("res://assets/fonts/Roboto-latin-cyrillic-fallback.ttf")

const _ZH_DIR: String = "res://assets/fonts/candidates/zh/"

const _HAN_AVAILABLE_WGHTS: Array[int] = [400, 700]
const _YUAN_AVAILABLE_WGHTS: Array[int] = [500, 700]

const _JP_DIR: String = "res://assets/fonts/candidates/jp/"
const _JP_NOTO_VF: FontFile = preload("res://assets/fonts/candidates/jp/SourceHan-JP-VF.ttf")
const _JP_YUAN_AVAILABLE_WGHTS: Array[int] = [500, 700]

const _WGHT_TAG: int = 2003265652

const _TNUM_TAG: int = 1953396077

const _VARIATION_ENTRIES: Array = [
	{"font": preload("res://assets/fonts/Roboto-regular.tres"), "wght": 400},
	{"font": preload("res://assets/fonts/Roboto-medium.tres"), "wght": 500},
	{"font": preload("res://assets/fonts/Roboto-600.tres"), "wght": 600},
	{"font": preload("res://assets/fonts/Roboto-semibold.tres"), "wght": 600},
	{"font": preload("res://assets/fonts/Roboto-bold.tres"), "wght": 700},
	{"font": preload("res://assets/fonts/Roboto-bold-title.tres"), "wght": 800},
	{"font": preload("res://assets/fonts/Roboto-bold-title-spaced.tres"), "wght": 800},
]

const _DEFAULT_VARIATION: FontVariation = preload("res://assets/fonts/Roboto-regular.tres")

static var _last_en: int = -1
static var _last_zh: int = -1
static var _last_jp: int = -1


## 选择实验字体并更新主题和共享字体资源；配置未变化时跳过重复修改。
static func apply() -> void:
	GameState.migrate_saved_ab_groups_to_peek(
		[
			ABTestManager.font_test_en.key,
			ABTestManager.font_test_zh.key,
			ABTestManager.font_test_jp.key
		]
	)
	var groups: Dictionary = FontExperimentSelector.groups_for_language_family(
		LanguageManager.resolve_language_family(),
		_effective_group(ABTestManager.font_test_en, "en"),
		_effective_group(ABTestManager.font_test_zh, "zh"),
		_effective_group(ABTestManager.font_test_jp, "jp"),
		int(ABTestManager.font_test_en.default_value),
		int(ABTestManager.font_test_zh.default_value),
		int(ABTestManager.font_test_jp.default_value)
	)
	var en: int = int(groups["en"])
	var zh: int = int(groups["zh"])
	var jp: int = int(groups["jp"])
	if en == _last_en and zh == _last_zh and jp == _last_jp:
		return
	_last_en = en
	_last_zh = zh
	_last_jp = jp

	var en_font: FontFile = _resolve_en_font(en)

	ThemeDB.fallback_font = en_font
	en_font.fallbacks = _compose_fallbacks(
		_resolve_zh_font(zh, 400), _resolve_jp_font(jp, 400), 400
	)
	en_font.emit_changed()

	var use_tnum: bool = en != FontTestEnConfig.VALUE_ROBOTO

	for entry: Dictionary in _VARIATION_ENTRIES:
		var variation: FontVariation = entry["font"]
		variation.base_font = en_font
		variation.fallbacks = _compose_fallbacks(
			_resolve_zh_font(zh, int(entry["wght"])),
			_resolve_jp_font(jp, int(entry["wght"])),
			int(entry["wght"])
		)

		variation.opentype_features = {_TNUM_TAG: 1} if use_tnum else {}
		variation.emit_changed()

	ThemeDB.get_default_theme().default_font = _DEFAULT_VARIATION

	print("[FontSwapManager] applied en=%d zh=%d jp=%d" % [en, zh, jp])


## 对当前语言族优先读取预览实验值，其他语言按正常加载路径取值。
static func _effective_group(cfg: AbConfigBase, family: String) -> int:
	if cfg.is_value_loaded():
		return int(cfg.value())
	var peek_group: int = int(cfg.peek_value())
	if LanguageManager.resolve_language_family() != family:
		return int(cfg.value())
	return peek_group


## 按实验组选择英文字体，未命中时使用 Roboto。
static func _resolve_en_font(v: int) -> FontFile:
	match v:
		FontTestEnConfig.VALUE_BALOO2:
			return _EN_BALOO2
		FontTestEnConfig.VALUE_ALIMAMA:
			return _EN_ALIMAMA
		FontTestEnConfig.VALUE_GEOM_EN:
			return _EN_GEOM
	return _EN_ROBOTO


## 按组和字重定位中文子集，资源未交付时返回空让后续字体兜底。
static func _resolve_zh_font(group_value: int, wght: int) -> FontFile:
	if group_value == FontTestZhConfig.VALUE_NONE:
		return null
	var path: String = ""
	match group_value:
		FontTestZhConfig.VALUE_HAN_SAN_QUAN_YUAN:
			path = _ZH_DIR + "HanSanQuanYuan-%s.ttf" % _bucket_name(wght, _HAN_AVAILABLE_WGHTS)
		FontTestZhConfig.VALUE_YUAN_QUAN_YUAN_2TW:
			path = _ZH_DIR + "YuanQuanYuan-2TW-%s.otf" % _bucket_name(wght, _YUAN_AVAILABLE_WGHTS)
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("[FontSwapManager] zh subset missing: %s (waiting on 素材交付)" % path)
		return null
	return load(path) as FontFile


## 为日文选择可变字体实例或最接近字重的静态子集。
static func _resolve_jp_font(group_value: int, wght: int) -> Font:
	if group_value == FontTestJpConfig.VALUE_NONE:
		return null
	match group_value:
		FontTestJpConfig.VALUE_NOTO_WEIGHTED:
			var variation: FontVariation = FontVariation.new()
			variation.base_font = _JP_NOTO_VF
			variation.variation_opentype = {_WGHT_TAG: wght}
			return variation
		FontTestJpConfig.VALUE_YUAN_QUAN_YUAN_2TW:
			var path: String = (
				_JP_DIR
				+ "YuanQuanYuan-2TW-JP-%s.otf" % _bucket_name(wght, _JP_YUAN_AVAILABLE_WGHTS)
			)
			if not ResourceLoader.exists(path):
				push_warning("[FontSwapManager] jp subset missing: %s (waiting on 素材交付)" % path)
				return null
			return load(path) as FontFile
	return null


## 从已提供的字重中取差值最小者，避免请求不存在的字体文件。
static func _bucket_weight(wght: int, available: Array[int]) -> int:
	var best: int = available[0]
	var best_diff: int = 9999
	for w: int in available:
		var d: int = absi(wght - w)
		if d < best_diff:
			best_diff = d
			best = w
	return best


## 将选中的字重映射为资源文件名使用的字重后缀。
static func _bucket_name(wght: int, available: Array[int]) -> String:
	match _bucket_weight(wght, available):
		400:
			return "Regular"
		500:
			return "Medium"
		700:
			return "Bold"
	return "Regular"


## 按中文、日文、通用汉字与拉丁扩展的顺序构造缺字回退链。
static func _compose_fallbacks(zh_font: Font, jp_font: Font, wght: int) -> Array[Font]:
	var arr: Array[Font] = []
	if zh_font != null:
		arr.append(zh_font)
	if jp_font != null:
		arr.append(jp_font)
	arr.append(_NOTO_FALLBACK)

	arr.append(_make_en_fallback(wght))
	return arr


## 创建指定字重的拉丁与西里尔字符回退字体，补主字体未覆盖的字符。
static func _make_en_fallback(wght: int) -> FontVariation:
	var fv: FontVariation = FontVariation.new()
	fv.base_font = _EN_FALLBACK
	fv.variation_opentype = {_WGHT_TAG: wght}
	return fv
