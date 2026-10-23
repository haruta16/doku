## 实验配置 inter_unlock_memory：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name InterUnlockMemoryConfig

# ---- 门槛值（单位 MB） ----
const DEFAULT_UNLOCK_MEMORY_MB: int = 300 # 默认门槛：300MB


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "inter_unlock_memory"
	default_value = DEFAULT_UNLOCK_MEMORY_MB


func is_unlocked_for_device() -> bool:
	var physical_bytes: int = int(OS.get_memory_info().get("physical", -1))
	if physical_bytes <= 0:
		return true
	@warning_ignore("integer_division")
	var ram_mb: int = physical_bytes / (1024 * 1024)
	return ram_mb >= value()
