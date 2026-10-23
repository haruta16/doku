## 界面事件名字表：为窗口和界面模块之间的事件提供统一标识。
class_name UIEvents
extends RefCounted

@warning_ignore_start("unused_signal")
signal window_created(ui_name: String, win: UIFrameWindow)
## 窗口显示完成；订阅者 UITrackerObserver 靠它做页面/弹窗曝光埋点
## 注意：关闭动画途中又被 show_ui 打开时会打断关闭，这种情况不重复发本信号
signal window_shown(ui_name: String, win: UIFrameWindow)
## 窗口隐藏完成（关闭动画与 on_hide 都走完、已出栈）；弹窗队列 UIPopupQueue 靠它串行弹下一个
signal window_hidden(ui_name: String, win: UIFrameWindow)
@warning_ignore_restore("unused_signal")
