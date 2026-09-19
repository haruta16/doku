# 广告/免费角标：按 AB 合规配置在 AD 文字、AD 图标、+ 号之间切换，并提供 Free 态
class_name GameAdBadge
extends Control

# ---- 子节点引用 ----
@onready var _ad_icon: TextureRect = $GreenRoot/HBoxContainer/ADIcon # AD 图标 1
@onready var _ad_icon2: TextureRect = $GreenRoot/HBoxContainer/ADIcon2 # AD 图标 2（图标 + 文字组合）
@onready var _ad_icon3: TextureRect = $GreenRoot/HBoxContainer/ADIcon3 # 第三个图标位，用作 + 号
@onready var _ad_tag: RichTextLabel = $GreenRoot/HBoxContainer/ADTag # AD 文字


# 进树默认按合规配置显示
func _ready() -> void:
	show_ad()


# 需要显示 AD 文字的地区（语言代码里的地区后缀）
const _AD_TEXT_REGIONS: Array[String] = ["US", "CA", "GB", "IE", "AU", "NZ"] # 命中这些地区的语言才显示 AD 文字


# ================= 角标形态 =================
# 按 AB 合规配置决定 AD 的呈现方式
func show_ad() -> void:
	# 先全部收起、文字留空
	_ad_tag.visible = true
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = false
	var v: int = ABTestManager.ad_compliance_ui.value()
	match v:
		# 纯文字 AD
		AdComplianceUiConfig.VALUE_SHOW:
			_ad_tag.text = "AD"
		# 纯图标
		AdComplianceUiConfig.VALUE_SHOW_ICON:
			_ad_icon.visible = true
			_ad_tag.visible = false
		# 图标 + AD 文字
		AdComplianceUiConfig.VALUE_SHOW_ICON_TEXT:
			_ad_icon2.visible = true
			_ad_tag.text = "AD"
		# 分地区：AD 文字地区用文字，否则用图标
		AdComplianceUiConfig.VALUE_REGION_SPLIT:
			if _is_ad_text_region():
				_ad_tag.text = "AD"
			else:
				_ad_icon.visible = true
				_ad_tag.visible = false
		# 兜底：文字 AD
		_:
			_ad_tag.text = "AD"


# 图标 + AD 文字（供外部按需调用）
func show_icon_with_ad() -> void:
	_ad_icon.visible = false
	_ad_icon2.visible = true
	_ad_icon3.visible = false
	_ad_tag.text = "AD"
	_ad_tag.visible = true


# ================= 地区判断 =================
# 当前语言是否属于「必须显示 AD 文字」的地区
static func _is_ad_text_region() -> bool:
	var locale: String = LanguageManager.get_locale()
	var parts: PackedStringArray = locale.split("_")
	# 游戏内语言优先：xx_YY 取地区后缀
	if parts.size() >= 2:
		return parts[parts.size() - 1].to_upper() in _AD_TEXT_REGIONS
	if locale == "en":
		return true
	# 纯 en 也算需要 AD 文字
	var sys_parts: PackedStringArray = OS.get_locale().split("_")
	if sys_parts.size() >= 2:
		return sys_parts[sys_parts.size() - 1].to_upper() in _AD_TEXT_REGIONS
	# 再看系统语言兜底
	return false


# 显示 Free 角标
func show_free() -> void:
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = false
	_ad_tag.visible = true
	_ad_tag.text = "Free"


# 显示 + 号（引导去获取道具）
func show_plus() -> void:
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = true
	_ad_tag.visible = false
