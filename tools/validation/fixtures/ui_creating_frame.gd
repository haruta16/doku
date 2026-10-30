extends UIFrameWindow

@export var trigger_stage: String = "ready"
@export var action: String = "reenter"
@export var wait_on_hide: bool = false
@export var wait_on_close: bool = false
signal hide_release
signal close_release


func _ready() -> void:
	if trigger_stage == "visibility_create":
		visibility_changed.connect(func() -> void:
			if not visible: _act("visibility_create"))
	_act("ready")


func on_create() -> void:
	if has_meta("manager"):
		var manager: UIWindowManager = get_meta("manager")
		if manager.has_meta("created_hooks"):
			manager.get_meta("created_hooks").append(true)
	_act("create")


func on_show(_params: Dictionary = {}) -> void:
	_act("show")


func on_hide() -> void:
	if wait_on_hide:
		await hide_release


func _play_close_animation() -> void:
	if wait_on_close:
		await close_release
	else:
		await super._play_close_animation()


func _act(stage: String) -> void:
	if stage != trigger_stage:
		return
	match action:
		"reenter":
			var manager: UIWindowManager = get_meta("manager")
			var observations: Array = manager.get_meta("observations")
			observations.append(manager.show_ui(_ui_name))
		"close": close_requested.emit()
		"queue_free": queue_free()
		"destroy": _do_destroy()
		"free": free()
