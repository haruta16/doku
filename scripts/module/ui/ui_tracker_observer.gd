class_name UITrackerObserver
extends RefCounted


func _init(ev: UIEvents) -> void:
	ev.window_shown.connect(_on_window_shown)


func _on_window_shown(_ui_name: String, win: UIFrameWindow) -> void:
	if win == null or not is_instance_valid(win):
		return
	var dlg: String = win.get_dlg_name()
	if dlg != "":
		var extra: Dictionary = win.get_dlg_extra()
		Tracker.track_dlg_show(dlg, "", extra)
		return
	var scr: String = win.get_scr_name()
	if scr != "":
		Tracker.track_scr_show(scr, "")
