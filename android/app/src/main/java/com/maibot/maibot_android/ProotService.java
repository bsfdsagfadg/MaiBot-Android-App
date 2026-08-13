package com.maibot.maibot_android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.Timer;
import java.util.TimerTask;

public class ProotService extends Service {
    private static final String TAG = "ProotService";
    private static final String CHANNEL_ID = "maibot_native_backend";
    private PowerManager.WakeLock wakeLock;

    private ProotProcess maibotProcess;
    private ProotProcess napcatProcess;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MaiBot::BackendLock");
        wakeLock.acquire();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE);
        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("MaiBot 后台服务")
                .setContentText("容器与服务正在后台运行")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .build();
        startForeground(1002, notification);

        if (intent != null) {
            String action = intent.getAction();
            if ("STOP".equals(action)) {
                String bin = intent.getStringExtra("binPath");
                if (bin != null) {
                    try {
                        Runtime.getRuntime().exec(new String[]{bin + "/busybox", "killall", "-9", "proot"}).waitFor();
                    } catch (Exception e) {}
                }
                stopSelf();
                return START_NOT_STICKY;
            }
            
            String binPath = intent.getStringExtra("binPath");
            String homePath = intent.getStringExtra("homePath");
            String tmpPath = intent.getStringExtra("tmpPath");
            String ubuntuPath = intent.getStringExtra("ubuntuPath");
            
            if (binPath != null && homePath != null) {
                // 检测是否已经存在存活的容器进程，如果是 DartVM 崩溃后重连，则直接放行，不杀进程
                if (maibotProcess != null && !maibotProcess.isStopped && 
                    napcatProcess != null && !napcatProcess.isStopped) {
                    Log.i(TAG, "Native Backend 依然存活，拦截重复的启动请求，保护底层 PRoot 容器免受重置。");
                    return START_REDELIVER_INTENT;
                }
                
                Log.i(TAG, "执行容器环境清理与全新启动...");
                
                // 清理之前的锁
                File x1Lock = new File(tmpPath, ".X1-lock");
                if (x1Lock.exists()) x1Lock.delete();
                File x11Unix = new File(tmpPath, ".X11-unix");
                if (x11Unix.exists()) deleteRecursively(x11Unix);

                // Strict cleanup according to memory
                try {
                    Runtime.getRuntime().exec(new String[]{binPath + "/busybox", "killall", "-9", "proot"}).waitFor();
                } catch (Exception e) {
                    Log.e(TAG, "killall proot failed", e);
                }

                maibotProcess = new ProotProcess("MaiBot", 20001, binPath, homePath, tmpPath, ubuntuPath, "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nexport UV_LINK_MODE=copy\nexport PYTHONUNBUFFERED=1\ncd /root/MaiBot\n/root/.local/bin/uv run bot.py\n");
                maibotProcess.start();
                
                napcatProcess = new ProotProcess("NapCat", 20002, binPath, homePath, tmpPath, ubuntuPath, "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\ncd /root\nbash /root/launcher.sh\n");
                napcatProcess.start();
            }
        }
        return START_REDELIVER_INTENT;
    }

    @Override
    public void onDestroy() {
        if (maibotProcess != null) maibotProcess.stop();
        if (napcatProcess != null) napcatProcess.stop();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID, "Native Backend", NotificationManager.IMPORTANCE_LOW);
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) manager.createNotificationChannel(serviceChannel);
        }
    }
    
    private void deleteRecursively(File fileOrDirectory) {
        if (fileOrDirectory.isDirectory()) {
            for (File child : fileOrDirectory.listFiles()) {
                deleteRecursively(child);
            }
        }
        fileOrDirectory.delete();
    }

    private class ProotProcess {
        private String name;
        private int port;
        private String binPath;
        private String homePath;
        private String tmpPath;
        private String ubuntuPath;
        private String command;

        private Process process;
        private ServerSocket serverSocket;
        private List<Socket> clients = new ArrayList<>();
        private LinkedList<byte[]> history = new LinkedList<>();
        private int historyLength = 0;
        private static final int MAX_HISTORY = 70000;
        
        private int restartCount = 0;
        private Timer restartTimer;
        boolean isStopped = false;

        public ProotProcess(String name, int port, String binPath, String homePath, String tmpPath, String ubuntuPath, String command) {
            this.name = name;
            this.port = port;
            this.binPath = binPath;
            this.homePath = homePath;
            this.tmpPath = tmpPath;
            this.ubuntuPath = ubuntuPath;
            this.command = command;
        }

        public void start() {
            if (isStopped) return;
            try {
                if (serverSocket == null) {
                    serverSocket = new ServerSocket(port);
                    new Thread(() -> {
                        while (!isStopped) {
                            try {
                                Socket client = serverSocket.accept();
                                synchronized (clients) {
                                    clients.add(client);
                                }
                                new Thread(() -> {
                                    try {
                                        OutputStream out = client.getOutputStream();
                                        out.write("\u0002__HIST_START__\u0003".getBytes());
                                        synchronized (clients) {
                                            for (byte[] chunk : history) out.write(chunk);
                                        }
                                        out.write("\u0002__HIST_END__\u0003".getBytes());
                                        
                                        InputStream in = client.getInputStream();
                                        byte[] inBuffer = new byte[1024];
                                        int inRead;
                                        while (!isStopped && (inRead = in.read(inBuffer)) != -1) {
                                            if (process != null) {
                                                OutputStream pStdin = process.getOutputStream();
                                                if (pStdin != null) {
                                                    pStdin.write(inBuffer, 0, inRead);
                                                    pStdin.flush();
                                                }
                                            }
                                        }
                                    } catch (IOException e) {
                                        // Client disconnected
                                    } finally {
                                        try { client.close(); } catch (IOException e) {}
                                        synchronized (clients) { clients.remove(client); }
                                    }
                                }).start();
                            } catch (IOException e) {
                                if (!isStopped) Log.e(TAG, name + " accept error", e);
                            }
                        }
                    }).start();
                }

                history.clear();
                historyLength = 0;
                
                List<String> cmd = new ArrayList<>(java.util.Arrays.asList(binPath + "/proot", "-0", "-r", ubuntuPath, "--link2symlink", "-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", tmpPath + ":/tmp", "-w", "/root"));
                
                // Fake sysdata bindings to prevent Python/uv crashes on restricted Android /proc
                String[] fakeProcs = {".loadavg", ".stat", ".uptime", ".version", ".vmstat", ".sysctl_entry_cap_last_cap", ".sysctl_inotify_max_user_watches"};
                String[] targetProcs = {"/proc/loadavg", "/proc/stat", "/proc/uptime", "/proc/version", "/proc/vmstat", "/proc/sys/kernel/cap_last_cap", "/proc/sys/fs/inotify/max_user_watches"};
                for (int i = 0; i < fakeProcs.length; i++) {
                    File fakeFile = new File(ubuntuPath + "/proc/" + fakeProcs[i]);
                    if (fakeFile.exists()) {
                        cmd.add("-b");
                        cmd.add(fakeFile.getAbsolutePath() + ":" + targetProcs[i]);
                    }
                }
                cmd.add("/bin/sh");
                
                ProcessBuilder pb = new ProcessBuilder(cmd);
                pb.environment().put("PATH", binPath + ":/system/bin:/system/xbin");
                pb.environment().put("HOME", homePath);
                pb.environment().put("PROOT_TMP_DIR", tmpPath);
                pb.environment().put("PROOT_LOADER", binPath + "/loader");
                pb.environment().put("LD_LIBRARY_PATH", binPath);
                pb.environment().put("TERM", "xterm-256color");
                pb.environment().put("EULA_AGREE", "agreed");
                pb.environment().put("PRIVACY_AGREE", "agreed");
                pb.redirectErrorStream(true);
                process = pb.start();

                OutputStream stdin = process.getOutputStream();
                stdin.write((command + "\n").getBytes());
                stdin.flush();

                InputStream stdout = process.getInputStream();
                new Thread(() -> {
                    byte[] buffer = new byte[4096];
                    int read;
                    try {
                        while ((read = stdout.read(buffer)) != -1) {
                            byte[] chunk = new byte[read];
                            System.arraycopy(buffer, 0, chunk, 0, read);
                            synchronized (clients) {
                                history.add(chunk);
                                historyLength += read;
                                while (historyLength > MAX_HISTORY && history.size() > 1) {
                                    historyLength -= history.removeFirst().length;
                                }
                                List<Socket> deadClients = new ArrayList<>();
                                for (Socket client : clients) {
                                    try {
                                        client.getOutputStream().write(chunk);
                                    } catch (IOException e) {
                                        try { client.close(); } catch (IOException ex) {}
                                        deadClients.add(client);
                                    }
                                }
                                clients.removeAll(deadClients);
                            }
                        }
                    } catch (IOException e) {
                        Log.e(TAG, name + " read error", e);
                    }
                    
                    if (!isStopped) {
                        scheduleRestart();
                    }
                }).start();

            } catch (Exception e) {
                Log.e(TAG, name + " start error", e);
                scheduleRestart();
            }
        }

        private void scheduleRestart() {
            if (restartCount >= 10) return;
            int delay = Math.min(3 * (1 << restartCount), 60);
            restartCount++;
            Log.i(TAG, name + " exited, restarting in " + delay + "s");
            restartTimer = new Timer();
            restartTimer.schedule(new TimerTask() {
                @Override
                public void run() {
                    start();
                }
            }, delay * 1000L);
        }

        public void stop() {
            isStopped = true;
            if (restartTimer != null) restartTimer.cancel();
            if (process != null) process.destroy();
            if (serverSocket != null) {
                try { serverSocket.close(); } catch (IOException e) {}
            }
            synchronized (clients) {
                for (Socket client : clients) {
                    try { client.close(); } catch (IOException e) {}
                }
                clients.clear();
            }
        }
    }
}