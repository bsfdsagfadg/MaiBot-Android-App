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
        try {
            startForeground(1002, notification);
        } catch (Exception e) {
            Log.e(TAG, "startForeground error", e);
        }
        if (intent != null) {
            String action = intent.getAction();
            if ("STOP".equals(action)) {
                if (maibotProcess != null) maibotProcess.stop();
                if (napcatProcess != null) napcatProcess.stop();
                String bin = intent.getStringExtra("binPath");
                if (bin != null) {
                    try {
                        Runtime.getRuntime().exec(new String[]{bin + "/busybox", "killall", "-9", "proot", "qq", "python", "python3", "node", "bash", "sh"}).waitFor();
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
                // 检测是否已经存在存活的容器进程，如果是 DartVM 退出/重启后重连，则直接放行，不杀进程
                if (maibotProcess != null && maibotProcess.isAlive() && 
                    napcatProcess != null && napcatProcess.isAlive()) {
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
                    Runtime.getRuntime().exec(new String[]{binPath + "/busybox", "killall", "-9", "proot", "qq", "python", "python3", "node", "bash", "sh"}).waitFor();
                } catch (Exception e) {
                    Log.e(TAG, "killall processes failed", e);
                }

                String maibotCmd = "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n" +
                        "export TERM=xterm-256color\n" +
                        "export COLORTERM=truecolor\n" +
                        "export FORCE_COLOR=1\n" +
                        "export CLICOLOR_FORCE=1\n" +
                        "export CLICOLOR=1\n" +
                        "export PYTHONUNBUFFERED=1\n" +
                        "export PYTHONIOENCODING=utf-8\n" +
                        "export PYTHON_COLORS=1\n" +
                        "export RICH_FORCE_COLOR=1\n" +
                        "export LOGURU_COLORIZE=true\n" +
                        "export UV_COLOR=always\n" +
                        "export UV_PROGRESS_MODE=visual\n" +
                        "export UV_NO_PROGRESS=0\n" +
                        "export UV_INDEX_URL=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple\n" +
                        "export PIP_NO_COLOR=0\n" +
                        "export COLUMNS=100\n" +
                        "export LINES=30\n" +
                        "export LANG=C.UTF-8\n" +
                        "export LC_ALL=C.UTF-8\n" +
                        "export UV_LINK_MODE=copy\n" +
                        "export TMPDIR=/tmp\n" +
                        "export TEMP=/tmp\n" +
                        "export TMP=/tmp\n" +
                        "mkdir -p /tmp /var/tmp\n" +
                        "cd /root/MaiBot\n" +
                        "if [ -f EULA.md ]; then export EULA_AGREE=$(md5sum EULA.md | awk '{print $1}'); fi\n" +
                        "if [ -f PRIVACY.md ]; then export PRIVACY_AGREE=$(md5sum PRIVACY.md | awk '{print $1}'); fi\n" +
                        "if command -v script >/dev/null 2>&1; then\n" +
                        "    exec script -q -e -c \"stty cols 45 rows 24 2>/dev/null; /root/.local/bin/uv run --color always bot.py\" /dev/null\n" +
                        "else\n" +
                        "    exec /root/.local/bin/uv run --color always bot.py\n" +
                        "fi\n";
                maibotProcess = new ProotProcess("MaiBot", 20001, binPath, homePath, tmpPath, ubuntuPath, maibotCmd);
                maibotProcess.start();
                
                String napcatCmd = "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n" +
                        "export TERM=xterm-256color\n" +
                        "export COLORTERM=truecolor\n" +
                        "export FORCE_COLOR=1\n" +
                        "export CLICOLOR_FORCE=1\n" +
                        "export CLICOLOR=1\n" +
                        "export COLUMNS=100\n" +
                        "export LINES=30\n" +
                        "export LANG=C.UTF-8\n" +
                        "export LC_ALL=C.UTF-8\n" +
                        "export TMPDIR=/tmp\n" +
                        "export TEMP=/tmp\n" +
                        "export TMP=/tmp\n" +
                        "mkdir -p /tmp /var/tmp\n" +
                        "cd /root\n" +
                        "bash /root/launcher.sh\n";
                napcatProcess = new ProotProcess("NapCat", 20002, binPath, homePath, tmpPath, ubuntuPath, napcatCmd);
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
                    serverSocket = new ServerSocket();
                    serverSocket.setReuseAddress(true);
                    serverSocket.bind(new java.net.InetSocketAddress("127.0.0.1", port));
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
                                        List<byte[]> historySnapshot;
                                        synchronized (clients) {
                                            historySnapshot = new ArrayList<>(history);
                                        }
                                        for (byte[] chunk : historySnapshot) {
                                            out.write(chunk);
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
                
                List<String> cmd = new ArrayList<>(java.util.Arrays.asList(binPath + "/proot", "-0", "-r", ubuntuPath, "--link2symlink", "-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", tmpPath + ":/tmp", "-b", tmpPath + ":/dev/shm", "-w", "/root"));
                
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
                pb.environment().put("HOME", "/root");
                pb.environment().put("PROOT_TMP_DIR", tmpPath);
                pb.environment().put("PROOT_LOADER", binPath + "/loader");
                pb.environment().put("LD_LIBRARY_PATH", binPath);
                pb.environment().put("TERM", "xterm-256color");
                pb.environment().put("COLORTERM", "truecolor");
                pb.environment().put("FORCE_COLOR", "1");
                pb.environment().put("CLICOLOR_FORCE", "1");
                pb.environment().put("CLICOLOR", "1");
                pb.environment().put("PYTHONUNBUFFERED", "1");
                pb.environment().put("PYTHONIOENCODING", "utf-8");
                pb.environment().put("PYTHON_COLORS", "1");
                pb.environment().put("RICH_FORCE_COLOR", "1");
                pb.environment().put("LOGURU_COLORIZE", "true");
                pb.environment().put("UV_COLOR", "always");
                pb.environment().put("UV_PROGRESS_MODE", "visual");
                pb.environment().put("UV_NO_PROGRESS", "0");
                pb.environment().put("UV_INDEX_URL", "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple");
                pb.environment().put("PIP_NO_COLOR", "0");
                pb.environment().put("COLUMNS", "100");
                pb.environment().put("LINES", "30");
                pb.environment().put("LANG", "C.UTF-8");
                pb.environment().put("LC_ALL", "C.UTF-8");
                pb.environment().put("TMPDIR", "/tmp");
                pb.environment().put("TEMP", "/tmp");
                pb.environment().put("TMP", "/tmp");
                pb.redirectErrorStream(true);
                process = pb.start();
                OutputStream stdin = process.getOutputStream();
                stdin.write((command + "\n").getBytes());
                stdin.flush();

                final long processStartTime = System.currentTimeMillis();
                InputStream stdout = process.getInputStream();
                new Thread(() -> {
                    byte[] buffer = new byte[4096];
                    int read;
                    try {
                        while ((read = stdout.read(buffer)) != -1) {
                            byte[] chunk = new byte[read];
                            System.arraycopy(buffer, 0, chunk, 0, read);
                            List<Socket> currentClients;
                            synchronized (clients) {
                                history.add(chunk);
                                historyLength += read;
                                while (historyLength > MAX_HISTORY && history.size() > 1) {
                                    historyLength -= history.removeFirst().length;
                                }
                                currentClients = new ArrayList<>(clients);
                            }
                            List<Socket> deadClients = new ArrayList<>();
                            for (Socket client : currentClients) {
                                try {
                                    client.getOutputStream().write(chunk);
                                } catch (IOException e) {
                                    try { client.close(); } catch (IOException ex) {}
                                    deadClients.add(client);
                                }
                            }
                            if (!deadClients.isEmpty()) {
                                synchronized (clients) {
                                    clients.removeAll(deadClients);
                                }
                            }
                        }
                    } catch (IOException e) {
                        Log.e(TAG, name + " read error", e);
                    }
                    
                    if (!isStopped) {
                        if (System.currentTimeMillis() - processStartTime > 60000L) {
                            restartCount = 0;
                        }
                        scheduleRestart();
                    }
                }).start();

            } catch (Exception e) {
                Log.e(TAG, name + " start error", e);
                scheduleRestart();
            }
        }

        private synchronized void scheduleRestart() {
            if (isStopped || restartCount >= 10) return;
            if (restartTimer != null) {
                restartTimer.cancel();
                restartTimer = null;
            }
            int delay = Math.min(3 * (1 << restartCount), 60);
            restartCount++;
            Log.i(TAG, name + " exited, restarting in " + delay + "s");
            restartTimer = new Timer();
            restartTimer.schedule(new TimerTask() {
                @Override
                public void run() {
                    synchronized (ProotProcess.this) {
                        if (!isStopped) {
                            start();
                        }
                    }
                }
            }, delay * 1000L);
        }

        public boolean isAlive() {
            if (isStopped || process == null) return false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                return process.isAlive();
            }
            try {
                process.exitValue();
                return false;
            } catch (IllegalThreadStateException e) {
                return true;
            }
        }

        public synchronized void stop() {
            isStopped = true;
            restartCount = 0;
            if (restartTimer != null) {
                restartTimer.cancel();
                restartTimer = null;
            }
            if (process != null) {
                process.destroy();
                process = null;
            }
            if (serverSocket != null) {
                try { serverSocket.close(); } catch (IOException e) {}
                serverSocket = null;
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