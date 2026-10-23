## 语言调试页签：提供多语言切换入口，便于检查翻译和字体表现。
class_name CheatTabLang
extends CheatTabBase


func title() -> String:
	return "语言"


func build(content: ScrollContainer, _panel: CheatPanel) -> void:
	ScrollDragHelper.attach(content)
	const LANG_DEFS: Array = [
		["en", "英语"],
		["zh_CN", "简体中文"],
		["pt_BR", "葡萄牙语(巴西)"],
		["hi", "印地语"],
		["id", "印尼语"],
		["fil", "菲律宾语"],
		["zh_TW", "繁体中文(台湾)"],
		["ru", "俄语"],
		["ja", "日语"],
		["de", "德语"],
		["fr", "法语"],
		["ko", "韩语"],
		["pt", "葡萄牙语"],
		["es", "西班牙语"],
		["az", "阿塞拜疆语"],
		["be", "白俄罗斯语"],
		["hr", "克罗地亚语"],
		["cs", "捷克语"],
		["da", "丹麦语"],
		["ar_EG", "阿拉伯语(埃及)"],
		["fi", "芬兰语"],
		["el", "希腊语"],
		["hu", "匈牙利语"],
		["fa", "波斯语"],
		["he", "希伯来语"],
		["it", "意大利语"],
		["ar_LB", "阿拉伯语(黎巴嫩)"],
		["lt", "立陶宛语"],
		["ms", "马来语"],
		["ar_MA", "阿拉伯语(摩洛哥)"],
		["nl_NL", "荷兰语"],
		["no", "挪威语"],
		["ar_OM", "阿拉伯语(阿曼)"],
		["en_PH", "英语(菲律宾)"],
		["pl", "波兰语"],
		["ro", "罗马尼亚语"],
		["ar_SA", "阿拉伯语(沙特)"],
		["sk", "斯洛伐克语"],
		["sv", "瑞典语"],
		["th", "泰语"],
		["ar_TN", "阿拉伯语(突尼斯)"],
		["tr", "土耳其语"],
		["uk", "乌克兰语"],
		["ar_AE", "阿拉伯语(阿联酋)"],
		["uz", "乌兹别克语"],
		["vi", "越南语"],
		["af", "南非荷兰语"],
		["am", "阿姆哈拉语"],
		["bn", "孟加拉语"],
		["bs", "波斯尼亚语"],
		["ca", "加泰罗尼亚语"],
		["es_ES", "西班牙语(西班牙)"],
		["es_MX", "西班牙语(墨西哥)"],
		["es_US", "西班牙语(美洲)"],
		["fr_CA", "法语(加拿大)"],
		["gu", "古吉拉特语"],
		["is", "冰岛语"],
		["kk", "哈萨克语"],
		["km", "高棉语"],
		["kn", "卡纳达语"],
		["lo", "老挝语"],
		["mk", "马其顿语"],
		["ml", "马拉雅拉姆语"],
		["mn", "蒙古语"],
		["mr", "马拉地语"],
		["ne", "尼泊尔语"],
		["pa", "旁遮普语"],
		["pt_PT", "葡萄牙语(葡萄牙)"],
		["si", "僧伽罗语"],
		["sl", "斯洛文尼亚语"],
		["sr", "塞尔维亚语"],
		["sw", "斯瓦希里语"],
		["ta", "泰米尔语"],
		["te", "泰卢固语"],
		["ur", "乌尔都语"],
	]
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	content.add_child(flow)

	var sys_btn := Button.new()
	sys_btn.text = "跟随系统"
	sys_btn.add_theme_font_size_override("font_size", 44)
	sys_btn.pressed.connect(func() -> void: _apply_locale(""))
	flow.add_child(sys_btn)
	sys_btn.custom_minimum_size = Vector2(sys_btn.get_minimum_size().x + 30, 100)

	for d in LANG_DEFS:
		var code: String = d[0]
		var btn := Button.new()
		btn.text = d[1]
		btn.add_theme_font_size_override("font_size", 44)
		btn.pressed.connect(func() -> void: _apply_locale(code))
		flow.add_child(btn)
		btn.custom_minimum_size = Vector2(btn.get_minimum_size().x + 30, 100)


func _apply_locale(locale: String) -> void:
	if locale == "" or locale == "clear" or locale == "system":
		GameState.set_apply_locale("")
		LanguageManager.apply_system_locale()
		FontSwapManager.apply()
		print("[Cheat] locale 覆盖已清除,跟随系统 = ", LanguageManager.get_locale())
		return
	LanguageManager.set_locale(locale)
	GameState.set_apply_locale(locale)
	print("[Cheat] locale = ", LanguageManager.get_locale(), " (已落盘)")
