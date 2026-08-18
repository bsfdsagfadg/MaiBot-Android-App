package com.maibot.maibot_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 接收来自常驻通知栏操作按钮的退出指令
 */
class ExitReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ExitReceiver"
        const val ACTION_EXIT = "com.maibot.maibot_android.ACTION_EXIT"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (ACTION_EXIT == intent.action) {
            Log.i(TAG, "收到通知栏退出指令广播")

            val mainActivity = MainActivity.instance
            // 1. 若 MainActivity 存活，委托 Flutter 层执行统一安全退出逻辑
            if (mainActivity != null && !mainActivity.isFinishing) {
                Log.i(TAG, "MainActivity 存活，委托 Flutter 层执行安全终止退出")
                mainActivity.triggerExitFromFlutter()
            } else {
                // 2. 若 UI 已不在，直接发送 STOP 指令给原生后台服务彻底释放资源
                Log.i(TAG, "MainActivity 不在前台，直接停止 ProotService 后台守护")
                val stopIntent = Intent(context, ProotService::class.java).apply {
                    action = "STOP"
                }
                context.startService(stopIntent)
            }
        }
    }
}
