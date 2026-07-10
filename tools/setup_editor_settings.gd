extends SceneTree


func _initialize() -> void:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var workspace_root := project_root.get_base_dir()
	var android_sdk := workspace_root.path_join("tools/android-sdk")
	var java_sdk := OS.get_environment("JAVA_HOME").trim_suffix("\\").trim_suffix("/")
	if java_sdk.is_empty():
		java_sdk = "C:/Program Files/Microsoft/jdk-17.0.19.10-hotspot"

	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting("export/android/android_sdk_path", android_sdk)
	editor_settings.set_setting("export/android/java_sdk_path", java_sdk)
	print("Configured Android SDK: %s" % android_sdk)
	print("Configured Java SDK: %s" % java_sdk)
	quit()
