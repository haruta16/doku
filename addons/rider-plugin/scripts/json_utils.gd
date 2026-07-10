@tool


class_name JsonUtils

static func load_from_file(path: String) -> Variant:

    var file: = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("JsonUtils: Failed to open file: %s" % path)
        return null
    var text: = file.get_as_text()
    file.close()
    var data: Variant = JSON.parse_string(text)
    if data == null:
        push_warning("JsonUtils: Invalid JSON in file: %s" % path)
        return null
    return data

static func load_dict_from_file(path: String) -> Dictionary:

    var data: = load_from_file(path) as Dictionary
    return data
