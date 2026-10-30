## UI 生命周期同步通知；管理器先更新对应的生命周期记录，再调用监听者。
## 监听者可通过管理器关闭、重开或销毁窗口；后续监听者不能假定窗口仍处于事件发出时的状态。
## 需要继续操作时，先确认实例有效、仍归管理器持有，以及当前显示状态。
class_name UIEvents
extends RefCounted

## 窗口已挂树并调用 on_create、登记为可用实例；本次外层 show_ui 尚未开始显示。
signal window_created(ui_name: String, win: UIFrameWindow)
## 窗口显示已生效：已调用 on_show 并更新遮挡，不等待开场动画结束。
## 产品可订阅埋点或导航通知。
## 注意：关闭动画途中又被 show_ui 打开时会打断关闭，这种情况不重复发本信号
signal window_shown(ui_name: String, win: UIFrameWindow)
## 窗口隐藏完成（关闭动画与 on_hide 都走完、已出栈）。
signal window_hidden(ui_name: String, win: UIFrameWindow)
## 首次显示在 shown 发布前取消；退场已结束（正常完成或销毁），且已出栈。
## 与 window_hidden 互斥，取消不会被计作一次有效显示。
signal window_show_cancelled(ui_name: String, win: UIFrameWindow)
