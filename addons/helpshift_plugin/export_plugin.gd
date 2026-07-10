@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void :
    export_plugin = AndroidExportPlugin.new()
    add_export_plugin(export_plugin)

func _exit_tree() -> void :
    remove_export_plugin(export_plugin)
    export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
    var _plugin_name: String = "HelpshiftPlugin"

    func _supports_platform(platform: EditorExportPlatform) -> bool:
        return platform is EditorExportPlatformAndroid

    func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
        if debug:
            return PackedStringArray(["helpshift_plugin/bin/debug/helpshift-debug.aar"])
        return PackedStringArray(["helpshift_plugin/bin/release/helpshift-release.aar"])





    func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
        return PackedStringArray(["com.helpshift:helpshift-sdkx:10.4.0"])

    func _get_name() -> String:
        return _plugin_name
