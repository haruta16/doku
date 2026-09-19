# 主页设置按钮的 Y 锚点（autoload 单例 HomeSettingAnchor）
# 主页量好自己的坐标后广播，其它节点（FollowHomeSettingBtnY）据此对齐
extends Node

# 锚点变化广播：y 是设置按钮中心的全局 Y 坐标
signal anchor_changed(y: float)

# ---- 运行时状态 ----
const UNSET: float = -1.0 # 哨兵值：负数表示「还没量到」

var _y: float = UNSET # 当前锚点 Y，UNSET 表示主页还没上报


# 主页在布局完成后写入设置按钮中心 Y；负值忽略，与旧值几乎相同就不广播
func set_settingbtn_y(y: float) -> void:
	if y < 0.0 or is_equal_approx(_y, y): # 负值＝无效、值没变＝不重复广播，避免订阅者反复重排
		return
	_y = y
	anchor_changed.emit(_y) # 值真的变了才发信号


# 读锚点 Y（跟随者用）
func get_settingbtn_y() -> float:
	return _y


# 是否已经量到过有效值，取值前先判断
func has_value() -> bool:
	return _y >= 0.0 # 统一用这个判断代替自己比 -1
