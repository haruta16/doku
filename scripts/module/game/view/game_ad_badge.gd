class_name GameAdBadge
extends Control

@onready var _ad_icon: TextureRect = $GreenRoot/HBoxContainer/ADIcon
@onready var _ad_icon2: TextureRect = $GreenRoot/HBoxContainer/ADIcon2
@onready var _ad_icon3: TextureRect = $GreenRoot/HBoxContainer/ADIcon3
@onready var _ad_tag: RichTextLabel = $GreenRoot/HBoxContainer/ADTag


func _ready() -> void:
	show_ad()


const _AD_TEXT_REGIONS: Array[String] = ["US", "CA", "GB", "IE", "AU", "NZ"]


func show_ad() -> void:
	_ad_tag.visible = true
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = false
	var v: int = ABTestManager.ad_compliance_ui.value()
	match v:
		AdComplianceUiConfig.VALUE_SHOW:
			_ad_tag.text = "AD"
		AdComplianceUiConfig.VALUE_SHOW_ICON:
			_ad_icon.visible = true
			_ad_tag.visible = false
		AdComplianceUiConfig.VALUE_SHOW_ICON_TEXT:
			_ad_icon2.visible = true
			_ad_tag.text = "AD"
		AdComplianceUiConfig.VALUE_REGION_SPLIT:
			if _is_ad_text_region():
				_ad_tag.text = "AD"
			else:
				_ad_icon.visible = true
				_ad_tag.visible = false
		_:
			_ad_tag.text = "AD"


func show_icon_with_ad() -> void:
	_ad_icon.visible = false
	_ad_icon2.visible = true
	_ad_icon3.visible = false
	_ad_tag.text = "AD"
	_ad_tag.visible = true


static func _is_ad_text_region() -> bool:
	var locale: String = LanguageManager.get_locale()
	var parts: PackedStringArray = locale.split("_")
	if parts.size() >= 2:
		return parts[parts.size() - 1].to_upper() in _AD_TEXT_REGIONS
	if locale == "en":
		return true
	var sys_parts: PackedStringArray = OS.get_locale().split("_")
	if sys_parts.size() >= 2:
		return sys_parts[sys_parts.size() - 1].to_upper() in _AD_TEXT_REGIONS
	return false


func show_free() -> void:
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = false
	_ad_tag.visible = true
	_ad_tag.text = "Free"


func show_plus() -> void:
	_ad_icon.visible = false
	_ad_icon2.visible = false
	_ad_icon3.visible = true
	_ad_tag.visible = false
