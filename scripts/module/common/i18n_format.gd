# 百分比文本的多语言格式化：按当前语言决定小数点用「.」还是「,」、% 放前面还是后面
# 结算页、每日挑战等处统一走这里，避免各页面自己拼字符串
class_name I18nFormat
extends RefCounted


# 把已经是百分数的 value 格式化成带 % 的文本（12.3 → "12.3%" / "12,3%" / "%12,3"）
# decimals 是保留的小数位数
static func percent(value: float, decimals: int = 1) -> String:
	var num_fmt: String = "%." + str(decimals) + "f" # 拼出 "%.1f" 这样的格式串
	var num: String = num_fmt % value
	if _is_decimal_comma_locale():
		num = num.replace(".", ",")
	if _is_percent_prefix_locale():
		return "%" + num
	return num + "%"


# 土耳其语习惯把 % 写在数字前面
static func _is_percent_prefix_locale() -> bool:
	var locale: String = TranslationServer.get_locale()
	return locale.begins_with("tr")


# 用逗号当小数点的语言（欧陆为主）
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


# 当前语言是否用逗号作小数点；墨西哥 / 美国西班牙语例外，仍用点号
static func _is_decimal_comma_locale() -> bool:
	var locale: String = TranslationServer.get_locale()

	if locale == "es_MX" or locale == "es_US":
		return false
	var lang: String = locale.split("_")[0] # 只取语言码，如 "de_DE" → "de"
	return lang in _COMMA_DECIMAL_LANGS
