## 语言管理器：优先恢复用户选择，否则解析系统语言，并在切换时更新共享字体。
extends Node

# ---- 支持语言白名单 ----
## 系统语言的主语言码必须在表内才认；表中含 tl/in/iw/no 这些旧码，见下面的别名表
const SUPPORTED_LANGS: Array[String] = [
	"en",
	"zh",
	"pt",
	"hi",
	"id",
	"in",
	"fil",
	"tl",
	"ru",
	"ja",
	"de",
	"fr",
	"ko",
	"es",
	"az",
	"be",
	"hr",
	"cs",
	"da",
	"ar",
	"fi",
	"el",
	"hu",
	"fa",
	"he",
	"iw",
	"it",
	"lt",
	"ms",
	"nl",
	"no",
	"nb",
	"pl",
	"ro",
	"sk",
	"sv",
	"th",
	"tr",
	"uk",
	"uz",
	"vi",
	"af",
	"am",
	"bn",
	"bs",
	"ca",
	"gu",
	"is",
	"kk",
	"km",
	"kn",
	"lo",
	"mk",
	"ml",
	"mn",
	"mr",
	"ne",
	"pa",
	"si",
	"sl",
	"sr",
	"sw",
	"ta",
	"te",
	"ur",
]

# ---- 旧语言码 → 现用码 ----
## 部分系统仍返回废弃码（如 in、iw），这里映射成当前标准码再取完整 locale
const SYS_LANG_ALIAS: Dictionary = {"tl": "fil", "in": "id", "iw": "he", "no": "nb"}

## 两条路都走不通时的兜底语言
const FALLBACK_LOCALE: String = "en"


# ================= 对外接口 =================
## 优先使用存档中的主动选择，只有未选择时才跟随受支持的系统语言。
func apply_system_locale() -> void:
	# 启动时调一次：优先用玩家上次选的语言，没选过才跟随系统
	var apply_loc: String = GameState.get_apply_locale()
	# 存档里玩家选过的 locale（语言弹窗确认时写入）
	if apply_loc != "":
		TranslationServer.set_locale(apply_loc)
		return
	TranslationServer.set_locale(resolve_system_locale())


## 把 OS 语言解析成本项目支持的 locale：命中白名单返回系统完整 locale，否则回落 en
func resolve_system_locale() -> String:
	# 系统语言主码（如 zh、en）
	var sys_lang: String = OS.get_locale_language()
	# 命中白名单：先过别名表，再取系统完整 locale（如 zh_CN）
	if sys_lang in SUPPORTED_LANGS:
		return SYS_LANG_ALIAS[sys_lang] if SYS_LANG_ALIAS.has(sys_lang) else OS.get_locale()
	return FALLBACK_LOCALE


## 切换翻译语言后立即更新共享字体，确保语言与字形资源同步。
func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	FontSwapManager.apply()


## 当前生效的 locale
func get_locale() -> String:
	return TranslationServer.get_locale()


## 仅将英文、中文、日文归入字体实验语言族，其余语言返回空族名。
func resolve_language_family() -> String:
	var locale: String = TranslationServer.get_locale()
	if locale == "en" or locale.begins_with("en_"):
		return "en"
	if locale == "zh" or locale.begins_with("zh_"):
		return "zh"
	if locale == "ja" or locale.begins_with("ja_"):
		return "jp"
	return ""
