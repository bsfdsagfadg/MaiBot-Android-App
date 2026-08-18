package com.maibot.maibot_android;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.ViewGroup;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentActivity;
import androidx.fragment.app.FragmentManager;

import io.flutter.embedding.android.FlutterFragment;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;
import android.provider.Settings;
import android.text.TextUtils;

@SuppressWarnings("deprecation")
public class MainActivity extends FragmentActivity {
    public static MainActivity instance;
    FlutterFragment flutterFragment;
    private static final String TAG_FLUTTER_FRAGMENT = "flutter_fragment";
    private static final String ENGINE_ID = "my_engine_id";
    Context mContext;
    FragmentManager fragmentManager;
    // 文件选择器相关
    private static final int FILE_CHOOSER_REQUEST_CODE = 1;
    private ValueCallback<Uri[]> filePathCallback;

    // 双击返回退出相关
    private boolean doubleBackToExitPressedOnce = false;
    private static final int DOUBLE_BACK_INTERVAL = 2000; // 2秒内连续按返回键

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        instance = this;
        mContext = this;

        // 在 super.onCreate 之前确保 FlutterEngine 已放入 Cache 中，
        // 防止在 Activity 重建（如被 OOMKiller 回收后重新进入）时
        // FragmentManager 自动恢复 FlutterFragment 抛出 IllegalStateException:
        // "The requested cached FlutterEngine did not exist in the FlutterEngineCache: 'my_engine_id'"
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(ENGINE_ID);
        if (flutterEngine == null) {
            flutterEngine = new FlutterEngine(this.getApplicationContext(), null, false);
            flutterEngine.getDartExecutor().executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault());
            GeneratedPluginRegistrant.registerWith(flutterEngine);
            FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine);
        }
        setupMethodChannel(flutterEngine);

        super.onCreate(savedInstanceState);
        setContentView(com.maibot.maibot_android.R.layout.my_activity_layout);

        fragmentManager = getSupportFragmentManager();
        flutterFragment = (FlutterFragment) fragmentManager.findFragmentByTag(TAG_FLUTTER_FRAGMENT);
        if (flutterFragment == null) {
            flutterFragment = FlutterFragment.withCachedEngine(ENGINE_ID).build();
            fragmentManager
                    .beginTransaction()
                    .add(com.maibot.maibot_android.R.id.fl_container, flutterFragment, TAG_FLUTTER_FRAGMENT)
                    .commit();
        }
    }

    private void setupMethodChannel(FlutterEngine flutterEngine) {
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "maibot_channel").setMethodCallHandler((call, result) -> {
            if ("lib_path".equals(call.method)) {
                result.success(mContext.getApplicationContext().getApplicationInfo().nativeLibraryDir);
            } else if ("hide_from_recents".equals(call.method)) {
                boolean hide = call.argument("hide");
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                    android.app.ActivityManager.AppTask task = null;
                    android.app.ActivityManager am = (android.app.ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
                    for (android.app.ActivityManager.AppTask t : am.getAppTasks()) {
                        if (t.getTaskInfo().id == getTaskId()) {
                            task = t;
                            break;
                        }
                    }
                    if (task != null) {
                        task.setExcludeFromRecents(hide);
                        result.success(true);
                    } else {
                        result.error("ERROR", "Task not found", null);
                    }
                } else {
                    result.error("UNSUPPORTED", "API level < 21", null);
                }
            } else if ("start_native_backend".equals(call.method)) {
                String binPath = call.argument("binPath");
                String homePath = call.argument("homePath");
                String tmpPath = call.argument("tmpPath");
                String ubuntuPath = call.argument("ubuntuPath");
                Intent intent = new Intent(mContext, ProotService.class);
                intent.putExtra("binPath", binPath);
                intent.putExtra("homePath", homePath);
                intent.putExtra("tmpPath", tmpPath);
                intent.putExtra("ubuntuPath", ubuntuPath);
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    mContext.startForegroundService(intent);
                } else {
                    mContext.startService(intent);
                }
                result.success(true);
            } else if ("stop_native_backend".equals(call.method)) {
                String stopBinPath = call.argument("binPath");
                Intent intent = new Intent(mContext, ProotService.class);
                intent.setAction("STOP");
                intent.putExtra("binPath", stopBinPath);
                mContext.startService(intent);
                result.success(true);
            } else if ("is_accessibility_enabled".equals(call.method)) {
                result.success(isAccessibilityServiceEnabled());
            } else if ("open_accessibility_settings".equals(call.method)) {
                try {
                    Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    mContext.startActivity(intent);
                    result.success(true);
                } catch (Exception e) {
                    result.error("OPEN_FAILED", e.getMessage(), null);
                }
            } else if ("is_auto_start_enabled".equals(call.method)) {
                android.content.SharedPreferences sp = mContext.getSharedPreferences("maibot_backend_prefs", Context.MODE_PRIVATE);
                result.success(sp.getBoolean("auto_start_enabled", true));
            } else if ("set_auto_start_enabled".equals(call.method)) {
                boolean enabled = Boolean.TRUE.equals(call.argument("enabled"));
                android.content.SharedPreferences sp = mContext.getSharedPreferences("maibot_backend_prefs", Context.MODE_PRIVATE);
                sp.edit().putBoolean("auto_start_enabled", enabled).apply();
                result.success(true);
            } else {
                result.notImplemented();
            }
        });
    }

    @Override
    public void onPostResume() {
        super.onPostResume();
        if (flutterFragment != null) {
            flutterFragment.onPostResume();
        }
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        if (flutterFragment != null) {
            flutterFragment.onNewIntent(intent);
        }
    }
    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        // 处理文件选择器返回的结果
        if (requestCode == FILE_CHOOSER_REQUEST_CODE) {
            if (filePathCallback == null) {
                return;
            }

            Uri[] results = null;
            if (resultCode == Activity.RESULT_OK && data != null) {
                String dataString = data.getDataString();
                if (dataString != null) {
                    results = new Uri[]{Uri.parse(dataString)};
                } else if (data.getClipData() != null) {
                    // 处理多文件选择
                    int count = data.getClipData().getItemCount();
                    results = new Uri[count];
                    for (int i = 0; i < count; i++) {
                        results[i] = data.getClipData().getItemAt(i).getUri();
                    }
                }
            }

            filePathCallback.onReceiveValue(results);
            filePathCallback = null;
        }

        // 传递给 FlutterFragment
        if (flutterFragment != null) {
            flutterFragment.onActivityResult(requestCode, resultCode, data);
        }
    }

    // 用于从 Flutter 端调用的方法，触发文件选择器
    public void openFileChooser(ValueCallback<Uri[]> callback) {
        filePathCallback = callback;

        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);

        Intent chooserIntent = Intent.createChooser(intent, "选择文件");
        startActivityForResult(chooserIntent, FILE_CHOOSER_REQUEST_CODE);
    }

    @Override
    public void onBackPressed() {
        if (flutterFragment != null) {
            flutterFragment.onBackPressed();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (flutterFragment != null) {
            flutterFragment.onRequestPermissionsResult(
                    requestCode,
                    permissions,
                    grantResults
            );
        }
    }

    @Override
    public void onUserLeaveHint() {
        if (flutterFragment != null) {
            flutterFragment.onUserLeaveHint();
        }
    }

    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (flutterFragment != null) {
            flutterFragment.onTrimMemory(level);
        }
    }
    private boolean isAccessibilityServiceEnabled() {
        try {
            android.view.accessibility.AccessibilityManager am = 
                    (android.view.accessibility.AccessibilityManager) mContext.getSystemService(Context.ACCESSIBILITY_SERVICE);
            if (am != null) {
                java.util.List<android.accessibilityservice.AccessibilityServiceInfo> services = 
                        am.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK);
                if (services != null) {
                    for (android.accessibilityservice.AccessibilityServiceInfo s : services) {
                        if (s.getId() != null && s.getId().startsWith(getPackageName())) {
                            return true;
                        }
                    }
                }
            }
        } catch (Exception ignored) {}

        int accessibilityEnabled = 0;
        final String expectedServiceName = getPackageName() + "/" + KeepAliveAccessibilityService.class.getCanonicalName();
        try {
            accessibilityEnabled = Settings.Secure.getInt(
                    mContext.getContentResolver(),
                    Settings.Secure.ACCESSIBILITY_ENABLED);
        } catch (Settings.SettingNotFoundException ignored) {}

        if (accessibilityEnabled == 1) {
            String settingValue = Settings.Secure.getString(
                    mContext.getContentResolver(),
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            if (settingValue != null) {
                TextUtils.SimpleStringSplitter splitter = new TextUtils.SimpleStringSplitter(':');
                splitter.setString(settingValue);
                while (splitter.hasNext()) {
                    String accessService = splitter.next();
                    if (accessService.equalsIgnoreCase(expectedServiceName) ||
                        accessService.contains(getPackageName() + "/.KeepAliveAccessibilityService") ||
                        accessService.contains(getPackageName() + "/com.maibot.maibot_android.KeepAliveAccessibilityService")) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    public void triggerExitFromFlutter() {
        runOnUiThread(() -> {
            FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(ENGINE_ID);
            if (flutterEngine != null) {
                new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "maibot_channel")
                        .invokeMethod("exit_app", null);
            } else {
                finishAffinity();
                System.exit(0);
            }
        });
    }

    @Override
    protected void onDestroy() {
        if (instance == this) {
            instance = null;
        }
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(ENGINE_ID);
        if (flutterEngine != null) {
            new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "maibot_channel").setMethodCallHandler(null);
        }
        super.onDestroy();
    }

}
