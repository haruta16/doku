@tool
extends RefCounted
class_name RiderLocatorService

var _installations_found: Array = []

var _rider_locator: RefCounted = null


var _last_selected_index: int = 0

func start_search() -> void :

    if not ClassDB.class_exists("RiderLocator"):
        return

    EditorSettingsUtil.show_rider_searching_state()
    if _rider_locator == null:
        _rider_locator = ClassDB.instantiate("RiderLocator")
        _rider_locator.connect("installations_loaded", _on_installations_loaded)
    _rider_locator.start_search()

func _on_installations_loaded(array: Array) -> void :
    _installations_found = array
    _update_selector()

func _update_selector() -> void :
    if _installations_found.is_empty():
        EditorSettingsUtil.erase_rider_external_editor_setting()
        return

    var index: = _index_for_exec_path(_installations_found)


    _last_selected_index = index
    EditorSettingsUtil.register_rider_installations(_installations_found, index)

    var settings_changed: = EditorInterface.get_editor_settings().settings_changed
    if not settings_changed.is_connected(_on_selection_changed):
        settings_changed.connect(_on_selection_changed)

func _index_for_exec_path(installations: Array) -> int:
    var current: = EditorSettingsUtil.get_external_editor_path()
    if current.is_empty():
        return 0
    for i in installations.size():
        if installations[i].get("path", "") == current:
            return i + 1
    return 0

func _on_selection_changed() -> void :
    var selected_index: = EditorSettingsUtil.get_rider_selector_index()


    if selected_index == _last_selected_index:
        return
    _last_selected_index = selected_index


    if selected_index == 0:
        return

    var installation_index: = selected_index - 1
    if installation_index >= 0 and installation_index < _installations_found.size():
        var installation = _installations_found[installation_index]
        var new_path: String = installation.get("path", "")
        if not new_path.is_empty():
            EditorSettingsUtil.set_external_editor_path(new_path)
