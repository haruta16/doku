## 实验配置 thumb_up：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ThumbUpConfig

# ---- 分组取值 ----
const VALUE_DISABLE_ALL: int = 0 # 全部关闭
const VALUE_LIKE_ONLY: int = 1 # 只点赞
const VALUE_CLAP_ONLY: int = 2 # 只鼓掌
const VALUE_BLOW_TRUMPET_ONLY: int = 3 # 只吹号
const VALUE_ALL_BY_PRIORITY: int = 4 # 吹号 > 鼓掌 > 点赞
const VALUE_CORRECTION_CHEER: int = 5 # 再加纠错欢呼
const VALUE_MISSED_CAT: int = 6 # 再加漏猫提醒
const VALUE_HAWK_EYE: int = 7 # 漏猫提醒换成专属动画
const VALUE_ALL_FIVE: int = 8 # 五种反馈全开
const VALUE_ALL_FIVE_RELAXED: int = 9 # 全开，但点赞间隔放宽
const VALUE_MAGNIFIER_CAT: int = 10
const VALUE_MISSED_CROSS: int = 11
const VALUE_ALL_FIVE_V3: int = 12

enum Feedback { BLOW_TRUMPET, CLAP, LIKE, MISSED_CROSS }


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "thumb_up"
	default_value = VALUE_MISSED_CROSS
