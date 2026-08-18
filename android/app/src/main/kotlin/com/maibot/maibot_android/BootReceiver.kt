package com.maibot.maibot_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 接收系统开机及应用更新广播，实现 PRoot 原生后台服务开机自启动
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        val action = intent.action
        Log.i(TAG, "收到系统启动/更新广播: $action")

        if (Intent.ACTION_BOOT_COMPLETED == action ||
            "android.intent.action.QUICKBOOT_POWERON" == action ||
            "com.htc.intent.action.QUICKBOOT_POWERON" == action ||
            Intent.ACTION_MY_PACKAGE_REPLACED == action
        ) {
            KeepAliveAccessibilityService.checkAndAutoStartBackend(context)
        }
    }
}
