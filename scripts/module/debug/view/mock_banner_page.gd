# 编辑器专用的假横幅广告条：按参数把一根 Control 贴到屏幕顶/底，不接任何广告 SDK
# 只在编辑器里注册（UIRegistry._EDITOR_PAGES），由 UniKitManager._mock_show_banner 拉起
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _bar: Control = $Bar # 就是那根假横幅
@onready var _info_label: Label = $Bar/InfoLabel # 显示 placement / position 的说明文字


# 显示前按 params 重算横幅位置：anchor_bottom 为真贴底，否则贴顶
func on_show(params: Dictionary = {}) -> void:
	visible = true
	var placement_id: String = params.get("placement_id", "banner") # 广告位 id，默认 banner
	var position: String = params.get("position", "") # 位置标识，只用于显示
	var anchor_bottom: bool = params.get("anchor_bottom", true) # true=贴屏幕底，false=贴顶
	var height_base: float = float(params.get("height_base", 180)) # 横幅高度（像素），默认 180
	var offset_base: float = float(params.get("offset_base", 0)) # 额外偏移（像素），用来模拟安全区或底部工具条留白

	# 先铺满整宽，左右不留边
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.offset_left = 0.0
	_bar.offset_right = 0.0
	# 贴底：offset 用负值从下边往上量
	if anchor_bottom:
		_bar.anchor_top = 1.0
		_bar.anchor_bottom = 1.0
		_bar.offset_top = -(height_base + offset_base)
		_bar.offset_bottom = -offset_base
	# 贴顶：offset 从上边往下量
	else:
		_bar.anchor_top = 0.0
		_bar.anchor_bottom = 0.0
		_bar.offset_top = offset_base
		_bar.offset_bottom = offset_base + height_base
	_info_label.text = "MOCK Banner  [%s / %s]" % [placement_id, position]
