## 重试参数的节奏扩展：保留本次取题实验组和节奏评分，避免重进丢失选题依据。
class_name PaceRetryAugmenter
extends RefCounted


## 原地把题目上的节奏组与分数复制到重试参数。
static func augment(retry_params: Dictionary, entry: Dictionary) -> void:
	retry_params["_bank_pace_group"] = entry.get("_bank_pace_group", 0)
	retry_params["_bank_pace_score"] = entry.get("_bank_pace_score", 0.0)
