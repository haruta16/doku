## 国际化数值格式工具：处理百分号位置、小数分隔符与翻译占位替换。
class_name I18nFormat
extends RefCounted


## 把已经是百分数的 value 格式化成带 % 的文本（12.3 → "12.3%" / "12,3%" / "%12,3"）
## decimals 是保留的小数位数
static func percent(value: float, decimals: int = 1) -> String:
	var num_fmt: String = "%." + str(decimals) + "f" # 拼出 "%.1f" 这样的格式串
	var num: String = num_fmt % value
	if _is_decimal_comma_locale():
		num = num.replace(".", ",")
	if _is_percent_prefix_locale():
		return "%" + num
	return num + "%"


static func fill(key: String, args: Variant) -> String:
	var template: String = TranslationServer.translate(key)
	if not template.replace("%%", "").contains("%"):
		return template
	return template % args


static func decimal(value: float, decimals: int = 1) -> String:
	var num_fmt: String = "%." + str(decimals) + "f"
	var num: String = num_fmt % value
	if _is_decimal_comma_locale():
		num = num.replace(".", ",")
	return num


## 土耳其语习惯把 % 写在数字前面
static func _is_percent_prefix_locale() -> bool:
	var locale: String = TranslationServer.get_locale()
	return locale.begins_with("tr")


## 用逗号当小数点的语言（欧陆为主）
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


## 当前语言是否用逗号作小数点；墨西哥 / 美国西班牙语例外，仍用点号
static func _is_decimal_comma_locale() -> bool:
	var locale: String = TranslationServer.get_locale()

	if locale == "es_MX" or locale == "es_US":
		return false
	var lang: String = locale.split("_")[0] # 只取语言码，如 "de_DE" → "de"
	return lang in _COMMA_DECIMAL_LANGS
