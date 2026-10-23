## 配置本机 Android 工具链。优先环境变量，再查仓库旁 ../tools 和系统常见目录。
## 只有路径真实可用时才写编辑器设置，不把旧机器的 Windows 路径复制到新机器。
extends SceneTree


func _initialize() -> void:
	call_deferred("_configure")


func _configure() -> void:
	# --editor 会启动文件扫描；等初始化完成再退出，避免中途打断导入线程。
	await process_frame
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var tools_root := project_root.get_base_dir().path_join("tools")
	var user_root := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	var android_sdk := _first_existing([
		OS.get_environment("ANDROID_HOME"), OS.get_environment("ANDROID_SDK_ROOT"),
		tools_root.path_join("android-sdk"), user_root.path_join("Library/Android/sdk"),
		user_root.path_join("Android/Sdk"), OS.get_environment("LOCALAPPDATA").path_join("Android/Sdk")
	], "platform-tools/adb.exe" if OS.get_name() == "Windows" else "platform-tools/adb")
	var java_sdk := _first_existing([
		OS.get_environment("JAVA_HOME"), tools_root.path_join("jdk-17/Contents/Home"),
		tools_root.path_join("jdk-17"), "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
		"/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
	], "bin/java.exe" if OS.get_name() == "Windows" else "bin/java")
	if java_sdk.is_empty() and OS.get_name() == "macOS":
		var output: Array = []
		if OS.execute("/usr/libexec/java_home", ["-v", "17"], output) == 0 and not output.is_empty():
			java_sdk = String(output[0]).strip_edges()
	if android_sdk.is_empty() or java_sdk.is_empty():
		push_error("Android SDK/JDK not found. Set ANDROID_HOME and JAVA_HOME, or install ../tools/android-sdk and ../tools/jdk-17. See docs/recovery/1.22.0/ANDROID_BUILD.md.")
		quit(1)
		return
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting("export/android/android_sdk_path", android_sdk)
	editor_settings.set_setting("export/android/java_sdk_path", java_sdk)
	print("Configured Android SDK: %s" % android_sdk)
	print("Configured Java SDK: %s" % java_sdk)
	quit()


func _first_existing(candidates: Array, relative_file: String) -> String:
	for candidate: String in candidates:
		if not candidate.is_empty() and FileAccess.file_exists(candidate.path_join(relative_file)):
			return candidate.trim_suffix("/").trim_suffix("\\")
	return ""
