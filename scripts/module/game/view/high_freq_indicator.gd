## 高频刷新指示控件：在逐帧回调中更新显示，供运行时观察刷新状态。
class_name HighFreqIndicator
extends Control

const COLOR_FULL: Color = Color(0.3, 0.85, 0.35)
const COLOR_EMPTY: Color = Color(0.95, 0.8, 0.2)

@onready var _fill: ColorRect = $Track/Fill


func _process(_delta: float) -> void:
	if OS.has_feature("rel"):
		visible = false
		set_process(false)
		return
	var cfg := ABTestManager.doubletap_protect
	if int(cfg.value()) == DoubletapProtectConfig.VALUE_CONTROL:
		visible = false
		return
	var cd: float = cfg.high_freq_cd_sec()
	var remaining: float = cfg.high_freq_remaining_sec()
	if cd <= 0.0 or remaining <= 0.0:
		visible = false
		return
	visible = true
	var frac: float = clampf(remaining / cd, 0.0, 1.0)
	_fill.anchor_right = frac
	_fill.color = COLOR_FULL.lerp(COLOR_EMPTY, 1.0 - frac)
