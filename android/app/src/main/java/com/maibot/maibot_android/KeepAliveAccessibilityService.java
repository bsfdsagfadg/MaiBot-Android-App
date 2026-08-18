package com.maibot.maibot_android;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;

/**
 * 无障碍保活服务
 * 用于提升进程在系统中的存活优先级，防止用户划掉后台任务卡片时导致主进程与 Linux 容器被直接终止
 */
public class KeepAliveAccessibilityService extends AccessibilityService {
    private static final String TAG = "KeepAliveAccessibility";
    private static boolean isServiceRunning = false;

    public static boolean isRunning() {
        return isServiceRunning;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // 无需拦截处理无障碍事件，仅作为系统级高优先级保活载体
    }

    @Override
    public void onInterrupt() {
        Log.i(TAG, "KeepAliveAccessibilityService onInterrupt");
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        isServiceRunning = true;
        Log.i(TAG, "KeepAliveAccessibilityService onServiceConnected: 无障碍保活服务已启动并在 :backend 进程生效");
        
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) {
            info = new AccessibilityServiceInfo();
        }
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_ALL_MASK;
        info.flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                | AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY
                | AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS;
        info.notificationTimeout = 0;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            info.flags |= AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE;
        }
        setServiceInfo(info);
    }

    @Override
    public void onTaskRemoved(android.content.Intent rootIntent) {
        Log.i(TAG, "onTaskRemoved: 用户划掉多任务卡片，无障碍服务继续锚定 :backend 进程");
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public void onDestroy() {
        isServiceRunning = false;
        Log.i(TAG, "KeepAliveAccessibilityService onDestroy: 无障碍保活服务已销毁");
        super.onDestroy();
    }
}
