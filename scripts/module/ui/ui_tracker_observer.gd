# 埋点旁听者：只订阅 UIEvents.window_shown，把窗口自报的 dlg/scr 名转给 Tracker
# 埋点逻辑集中在 Tracker，UIManager 本身不碰埋点，靠这个观察者解耦
class_name UITrackerObserver
extends RefCounted


# 构造时接上事件总线；由 UIManager._ready 创建并持有
func _init(ev: UIEvents) -> void:
	ev.window_shown.connect(_on_window_shown)


# 窗口显示回调：先看 dlg 名（弹窗，带 extra 参数），再看 scr 名（整页），都为空就不上报
func _on_window_shown(_ui_name: String, win: UIFrameWindow) -> void:
	if win == null or not is_instance_valid(win):
		return
	var dlg: String = win.get_dlg_name() # 弹窗类页面覆写 get_dlg_name 才会走这条分支
	if dlg != "":
		var extra: Dictionary = win.get_dlg_extra() # 弹窗曝光把 get_dlg_extra 的附加参数一起带上
		Tracker.track_dlg_show(dlg, "", extra)
		return
	var scr: String = win.get_scr_name() # 非弹窗页面按页面曝光上报
	if scr != "":
		Tracker.track_scr_show(scr, "")
