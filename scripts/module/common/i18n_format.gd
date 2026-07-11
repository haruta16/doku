class_name I18nFormat
extends RefCounted


static func percent(value: float, decimals: int = 1) -> String:
	var num_fmt: String = "%." + str(decimals) + "f"
	var num: String = num_fmt % value
	if _is_decimal_comma_locale():
		num = num.replace(".", ",")
	if _is_percent_prefix_locale():
		return "%" + num
	return num + "%"


static func _is_percent_prefix_locale() -> bool:
	var locale: String = TranslationServer.get_locale()
	return locale.begins_with("tr")


const _COMMA_DECIMAL_LANGS: Array[String] = [
	"de",
	"fr",
	"es",
	"pt",
	"it",
	"ru",
	"uk",
	"be",
	"pl",
	"cs",
	"sk",
	"sl",
	"hr",
	"sr",
	"bs",
	"mk",
	"ro",
	"hu",
	"el",
	"fi",
	"sv",
	"da",
	"no",
	"is",
	"nl",
	"ca",
	"tr",
	"az",
	"kk",
	"uz",
	"id",
	"vi",
	"af",
	"lt",
]


static func _is_decimal_comma_locale() -> bool:
	var locale: String = TranslationServer.get_locale()

	if locale == "es_MX" or locale == "es_US":
		return false
	var lang: String = locale.split("_")[0]
	return lang in _COMMA_DECIMAL_LANGS
