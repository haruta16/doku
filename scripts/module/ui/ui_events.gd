# UI 事件总线：UIManager 在窗口创建/显示/隐藏时广播，外部模块只订阅、不反向调用
class_name UIEvents
extends RefCounted

# 窗口场景实例化完成（此时还没显示）；由 UIManager._create_and_cache 发出，当前没有订阅者
signal window_created(ui_name: String, win: UIFrameWindow)
# 窗口显示完成；订阅者 UITrackerObserver 靠它做页面/弹窗曝光埋点
# 注意：关闭动画途中又被 show_ui 打开时会打断关闭，这种情况不重复发本信号
signal window_shown(ui_name: String, win: UIFrameWindow)
# 窗口隐藏完成（关闭动画与 on_hide 都走完、已出栈）；弹窗队列 UIPopupQueue 靠它串行弹下一个
signal window_hidden(ui_name: String, win: UIFrameWindow)
