class_name LevelBankIO
extends RefCounted








const _KEY: String = "meowdoku-2026-bank-secret"
const _EDITOR_DIR: String = "res://assets/editor/levels"
const _RUNTIME_DIR: String = "res://assets/resources/levels"



static func load_json(filename: String) -> Variant:
    var is_editor: bool = OS.has_feature("editor")
    var path: String = (_EDITOR_DIR if is_editor else _RUNTIME_DIR) + "/" + filename
    if not FileAccess.file_exists(path):
        return null
    var f: FileAccess = FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("LevelBankIO: cannot open %s" % path)
        return null
    var bytes: PackedByteArray = f.get_buffer(f.get_length())
    f.close()
    if not is_editor:
        _xor_inplace(bytes)
    var text: String = bytes.get_string_from_utf8()
    return JSON.parse_string(text)


static func _xor_inplace(bytes: PackedByteArray) -> void :
    var key_len: int = _KEY.length()
    if key_len == 0 or bytes.is_empty():
        return
    for i in bytes.size():
        bytes[i] ^= _KEY.unicode_at(i % key_len)
