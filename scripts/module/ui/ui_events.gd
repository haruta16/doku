class_name UIEvents
extends RefCounted

signal window_created(ui_name: String, win: UIFrameWindow)
signal window_shown(ui_name: String, win: UIFrameWindow)
signal window_hidden(ui_name: String, win: UIFrameWindow)
