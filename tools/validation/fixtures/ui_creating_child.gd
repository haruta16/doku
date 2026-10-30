## 创建过程的可控回调：验证真实 PackedScene 和 ready/create/show 顺序。
extends UIChildWindow

signal finish_hide
@export var stage: String = "show"
@export var action: String = "close"
@export var delayed_hide: bool = false
var owner_window: UIBaseWindow


func _ready() -> void:
	owner_window = get_parent() as UIBaseWindow
	if stage.begins_with("visibility_"):
		visibility_changed.connect(func() -> void:
			if (stage == "visibility_create" and not visible) or (stage == "visibility_show" and visible):
				_act()
		)
	if stage == "ready":
		_act()


func on_create() -> void:
	owner_window.get_meta("creation_events").append("create")
	if stage == "create":
		_act()


func on_show(_params: Dictionary = {}) -> void:
	owner_window.get_meta("creation_events").append("show")
	if stage == "show":
		_act()


func on_hide() -> void:
	if delayed_hide:
		await finish_hide


func on_destroy() -> void:
	if is_instance_valid(owner_window):
		owner_window.get_meta("creation_events").append("child_destroy")


func _act() -> void:
	match action:
		"close": owner_window.destroy_child(self)
		"destroy_owner": owner_window._do_destroy()
		"queue_free": queue_free()
