const bool product = bool.fromEnvironment('dart.vm.product');

class Config {
  // 应用包名
  static const String packageName = 'com.maibot.maibot_android';

  // 与原生侧通信的 MethodChannel 名称
  static const String methodChannel = 'maibot_channel';

  // Ubuntu系统镜像文件名
  static const String ubuntuFileName = 'ubuntu-noble-aarch64-pd-v4.18.0.tar.xz';

  // GitHub 仓库信息
  static const String githubOwner = 'bsfdsagfadg';
  static const String githubRepo = 'MaiBot-Android-App';
  static const String githubReleasesPath =
      '/repos/$githubOwner/$githubRepo/releases/latest';

  // GitHub API 镜像源列表（按优先级排序）
  static const List<String> githubApiMirrors = [
    'https://ghfast.top',
    'https://gh-proxy.com',
    'https://mirror.ghproxy.com',
    'https://hub.gitmirror.com',
  ];

  // GitHub 官方 API
  static const String githubApi = 'https://api.github.com';

  // GitHub 官方下载地址
  static const String githubDownloadBase =
      'https://github.com/$githubOwner/$githubRepo/releases/download';

  // 下载镜像源列表
  static const List<Map<String, String>> downloadMirrors = [
    {
      'name': 'Ghfast镜像下载',
      'icon': 'speed',
      'url': 'https://ghfast.top',
    },
    {
      'name': 'GHProxy镜像下载',
      'icon': 'speed',
      'url': 'https://gh-proxy.com',
    },
    {
      'name': 'Mirror GHProxy镜像下载',
      'icon': 'speed',
      'url': 'https://mirror.ghproxy.com',
    },
    {
      'name': 'Hub Gitmirror镜像下载',
      'icon': 'speed',
      'url': 'https://hub.gitmirror.com',
    },
  ];
}

/// 与前台服务 TaskHandler（独立 Isolate）通信的控制消息协议。
/// 跨 Isolate 的静态标志不可见，必须经 FlutterForegroundTask.sendDataToTask 传递。
class TaskMessages {
  static const String startMaibot = 'start_maibot';
  static const String startNapcat = 'start_napcat';
  static const String userStop = 'user_stop';
}

/// 本地服务端口常量
class Ports {
  // PTY 输出转发 Socket（前台服务监听，UI 侧连接）
  static const int maibotPtySocket = 20001;
  static const int napcatPtySocket = 20002;

  // Web 服务端口
  static const int maibotWeb = 8001;
  static const int napcatWebUi = 6099;

  // 就绪探测端口（MaiBot 启动完成后任一端口可连即视为就绪）
  static const List<int> localhostProbePorts = [8001, 6185];
}
