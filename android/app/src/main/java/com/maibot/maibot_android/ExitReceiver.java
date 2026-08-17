package com.maibot.maibot_android;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * 接收来自常驻通知栏操作按钮的退出指令
 */
public class ExitReceiver extends BroadcastReceiver {
    private static final String TAG = "ExitReceiver";
    public static final String ACTION_EXIT = "com.maibot.maibot_android.ACTION_EXIT";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null && ACTION_EXIT.equals(intent.getAction())) {
            Log.i(TAG, "收到通知栏退出指令广播");

            // 1. 若 MainActivity 存活，委托 Flutter 层执行统一安全退出逻辑
            if (MainActivity.instance != null && !MainActivity.instance.isFinishing()) {
                Log.i(TAG, "MainActivity 存活，委托 Flutter 层执行安全终止退出");
                MainActivity.instance.triggerExitFromFlutter();
            } else {
                // 2. 若 UI 已不在，直接发送 STOP 指令给原生后台服务彻底释放资源
                Log.i(TAG, "MainActivity 不在前台，直接停止 ProotService 后台守护");
                Intent stopIntent = new Intent(context, ProotService.class);
                stopIntent.setAction("STOP");
                context.startService(stopIntent);
            }
        }
    }
}
