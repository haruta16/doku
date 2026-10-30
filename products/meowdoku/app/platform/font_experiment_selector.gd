## 字体实验选择器：只让当前语言族参与实验，其余语言保留默认组。
class_name FontExperimentSelector
extends RefCounted


## 生成英、中、日三组配置，避免切换当前语言时同时改变其他语言的实验值。
static func groups_for_language_family(
	language_family: String,
	en_group: int,
	zh_group: int,
	jp_group: int,
	en_default: int,
	zh_default: int,
	jp_default: int
) -> Dictionary:
	match language_family:
		"en":
			return {"en": en_group, "zh": zh_default, "jp": jp_default}
		"zh":
			return {"en": en_default, "zh": zh_group, "jp": jp_default}
		"jp":
			return {"en": en_default, "zh": zh_default, "jp": jp_group}
		_:
			return {"en": en_default, "zh": zh_default, "jp": jp_default}
