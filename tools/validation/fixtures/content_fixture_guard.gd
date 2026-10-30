## 专项运行器生成标记，且工程必须位于该夹具目录内；不依赖某个平台的临时路径。
extends RefCounted


static func allows(directory: String) -> bool:
	var work := directory.replace("\\", "/").simplify_path().trim_suffix("/")
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	if not work.is_absolute_path() or project.get_base_dir() != work or project.get_file() not in ["project", "bootstrap-project"]:
		return false
	var marker := work.path_join(".content-test-fixture")
	return FileAccess.file_exists(marker) and FileAccess.get_file_as_string(marker) == "doku-isolated-content-v1\n"
