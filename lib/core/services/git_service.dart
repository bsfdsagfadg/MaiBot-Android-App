import 'dart:convert';
import 'dart:io';

import 'package:global_repository/global_repository.dart';

import '../constants/scripts.dart' as scripts;

class ProotExecResult {
  final bool success;
  final int exitCode;
  final String stdout;
  final String stderr;
  final String output;

  ProotExecResult({
    required this.success,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.output,
  });
}

class GitService {
  static const String maiBotPath = '/root/MaiBot';

  /// 检查 MaiBot 是否已克隆且具有 .git 目录
  static bool isMaiBotGitRepo() {
    final gitDir = Directory('${scripts.ubuntuPath}/root/MaiBot/.git');
    return gitDir.existsSync();
  }

  /// 在 PRoot 环境中执行命令并获取完整执行输出与日志
  static Future<ProotExecResult> runInProot(
    String command, {
    Function(String)? onLog,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final prootPath = '${RuntimeEnvir.binPath}/proot';
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);

    // 继承宿主机的代理配置（支持 VPN / 代理工具环境穿透）
    final envKeys = [
      'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy',
      'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
    ];
    final proxyExports = StringBuffer();
    for (final key in envKeys) {
      final val = Platform.environment[key];
      if (val != null && val.isNotEmpty) {
        proxyExports.write('export $key="$val"; ');
      }
    }

    final args = [
      '-0',
      '-r',
      scripts.ubuntuPath,
      '--link2symlink',
      '-b',
      '/dev',
      '-b',
      '/proc',
      '-b',
      '/sys',
      '-b',
      '${RuntimeEnvir.tmpPath}:/tmp',
      '-b',
      '${RuntimeEnvir.tmpPath}:/dev/shm',
      '-w',
      '/root',
      '/bin/sh',
      '-c',
      'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; '
          'export TERM=xterm-256color; '
          'export COLORTERM=truecolor; '
          'export FORCE_COLOR=1; '
          'export CLICOLOR_FORCE=1; '
          'export CLICOLOR=1; '
          'export PYTHONUNBUFFERED=1; '
          'export PYTHONIOENCODING=utf-8; '
          'export UV_COLOR=always; '
          'export UV_INDEX_URL=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple; '
          'export LANG=C.UTF-8; '
          'export LC_ALL=C.UTF-8; '
          'export DEBIAN_FRONTEND=noninteractive; '
          'export GIT_TERMINAL_PROMPT=0; '
          'export TMPDIR=/tmp; '
          'export TEMP=/tmp; '
          'export TMP=/tmp; '
          '${proxyExports.toString()}'
          'mkdir -p /tmp /var/tmp; '
          '$command'
    ];
    final env = {
      'PROOT_TMP_DIR': RuntimeEnvir.tmpPath,
      'LD_LIBRARY_PATH': RuntimeEnvir.binPath,
      'PROOT_LOADER': '${RuntimeEnvir.binPath}/loader',
      'TERM': 'xterm-256color',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
      'TMPDIR': '/tmp',
    };

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final allOutputBuffer = StringBuffer();

    try {
      final process = await Process.start(prootPath, args, environment: env);

      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        stdoutBuffer.write(data);
        allOutputBuffer.write(data);
        onLog?.call(data);
      });

      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        stderrBuffer.write(data);
        allOutputBuffer.write(data);
        onLog?.call(data);
      });

      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      });

      return ProotExecResult(
        success: exitCode == 0,
        exitCode: exitCode,
        stdout: stdoutBuffer.toString().trim(),
        stderr: stderrBuffer.toString().trim(),
        output: allOutputBuffer.toString().trim(),
      );
    } catch (e) {
      return ProotExecResult(
        success: false,
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
        output: '执行失败: $e',
      );
    }
  }

  /// 获取当前检出的分支名或 Tag 标识
  static Future<String> getCurrentRef() async {
    if (!isMaiBotGitRepo()) return '未安装';

    final res = await runInProot(
      'cd $maiBotPath && '
      'git config --global --add safe.directory "*" 2>/dev/null || true; '
      '(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)',
      timeout: const Duration(seconds: 10),
    );

    final ref = res.output.trim().split('\n').last.trim();
    return ref.isNotEmpty ? ref : '未知分支';
  }

  /// 动态拉取并获取所有远程分支列表（操作前全面 fetch）
  static Future<List<String>> getAvailableBranches({Function(String)? onLog}) async {
    if (!isMaiBotGitRepo()) return [];

    onLog?.call('正在从远端同步最新分支与引用信息 (git fetch)...\n');
    await runInProot(
      'cd $maiBotPath && '
      'git config --global --add safe.directory "*" 2>/dev/null || true; '
      'git config --system --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
      'git config --global --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
      'git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || true; '
      '(git -c gc.auto=0 fetch origin "+refs/heads/*:refs/remotes/origin/*" --prune 2>/dev/null || '
      'git -c gc.auto=0 fetch --all --prune 2>/dev/null || '
      'git -c gc.auto=0 fetch origin 2>/dev/null || true)',
      onLog: onLog,
      timeout: const Duration(seconds: 40),
    );

    final res = await runInProot(
      'cd $maiBotPath && git branch -r --no-color',
      timeout: const Duration(seconds: 10),
    );

    final branches = <String>{};
    for (final line in res.output.split('\n')) {
      var trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.contains('->') || trimmed.contains('HEAD')) {
        continue;
      }
      // 剥离远程前缀 (如 origin/main -> main, upstream/dev -> dev)
      if (trimmed.contains('/')) {
        trimmed = trimmed.substring(trimmed.indexOf('/') + 1);
      }
      if (trimmed.isNotEmpty) {
        branches.add(trimmed);
      }
    }

    // 同时补充本地分支
    final localRes = await runInProot(
      'cd $maiBotPath && git branch --format="%(refname:short)"',
      timeout: const Duration(seconds: 10),
    );
    for (final line in localRes.output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        branches.add(trimmed);
      }
    }

    final sorted = branches.toList()..sort();
    return sorted;
  }

  /// 动态获取所有 Release Tags 列表（操作前全面 fetch --tags）
  static Future<List<String>> getReleaseTags({Function(String)? onLog}) async {
    if (!isMaiBotGitRepo()) return [];

    onLog?.call('正在从远端同步 Release Tags (git fetch --tags)...\n');
    await runInProot(
      'cd $maiBotPath && '
      'git config --global --add safe.directory "*" 2>/dev/null || true; '
      'git config --system --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
      'git config --global --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
      'git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || true; '
      '(git -c gc.auto=0 fetch --tags --force origin 2>/dev/null || '
      'git -c gc.auto=0 fetch --tags --prune 2>/dev/null || '
      'git -c gc.auto=0 fetch origin 2>/dev/null || true)',
      onLog: onLog,
      timeout: const Duration(seconds: 40),
    );

    final res = await runInProot(
      'cd $maiBotPath && git tag -l --sort=-v:refname',
      timeout: const Duration(seconds: 10),
    );

    final tags = <String>[];
    for (final line in res.output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        tags.add(trimmed);
      }
    }

    return tags;
  }

  /// 执行 git pull 更新 MaiBot（前置全面 fetch 并自动同步依赖）
  static Future<ProotExecResult> pullMaiBot({Function(String)? onLog}) async {
    if (!isMaiBotGitRepo()) {
      return ProotExecResult(
        success: false,
        exitCode: -1,
        stdout: '',
        stderr: 'MaiBot 目录不存在或不是有效的 Git 仓库',
        output: 'MaiBot 目录不存在或不是有效的 Git 仓库',
      );
    }

    onLog?.call('1. 正在同步远程引用与代码 (git fetch & pull)...\n');
    final cmd = 'cd $maiBotPath && '
        'git config --global --add safe.directory "*" 2>/dev/null || true; '
        'git config --system --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
        'git config --global --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
        'git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || true; '
        'echo "[GIT] 同步远端最新分支与 Tag..." && '
        '(git -c gc.auto=0 fetch origin "+refs/heads/*:refs/remotes/origin/*" --tags --prune 2>/dev/null || '
        'git -c gc.auto=0 fetch --all --prune 2>/dev/null || true) && '
        'git stash 2>/dev/null || true; '
        'echo "[GIT] 合并最新代码..." && '
        '(git -c gc.auto=0 pull --rebase=false || git -c gc.auto=0 pull --rebase=false origin main || true) && '
        'if [ -f /root/.local/bin/uv ]; then '
        'echo "[UV] 检查并同步 Python 依赖库..." && '
        '/root/.local/bin/uv sync --no-progress; '
        'fi';

    return await runInProot(cmd, onLog: onLog, timeout: const Duration(minutes: 5));
  }

  /// 切换分支（前置精准 fetch 目标分支、稳健检出与同步依赖）
  static Future<ProotExecResult> switchBranch(
    String branchName, {
    Function(String)? onLog,
  }) async {
    if (!isMaiBotGitRepo()) {
      return ProotExecResult(
        success: false,
        exitCode: -1,
        stdout: '',
        stderr: 'MaiBot 仓库不存在',
        output: 'MaiBot 仓库不存在',
      );
    }

    onLog?.call('1. 正在从远端精准抓取分支: $branchName (git fetch)...\n');
    final cmd = 'cd $maiBotPath && '
        'git config --global --add safe.directory "*" 2>/dev/null || true; '
        'git config --system --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
        'git config --global --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
        'git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || true; '
        'echo "[GIT] 抓取目标分支 $branchName 远程引用..." && '
        '(git -c gc.auto=0 fetch origin "+refs/heads/$branchName:refs/remotes/origin/$branchName" 2>/dev/null || '
        'git -c gc.auto=0 fetch origin "$branchName" 2>/dev/null || '
        'git -c gc.auto=0 fetch origin "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || '
        'git -c gc.auto=0 fetch --all 2>/dev/null || true) && '
        'git stash 2>/dev/null || true; '
        'echo "[GIT] 正在检出分支 $branchName..." && '
        '(if git show-ref --verify --quiet "refs/heads/$branchName"; then '
        '    git -c gc.auto=0 checkout "$branchName" || git -c gc.auto=0 checkout -f "$branchName"; '
        'elif git show-ref --verify --quiet "refs/remotes/origin/$branchName"; then '
        '    git -c gc.auto=0 checkout -b "$branchName" --track "origin/$branchName" 2>/dev/null || '
        '    git -c gc.auto=0 checkout -B "$branchName" "origin/$branchName" || '
        '    git -c gc.auto=0 checkout -f "$branchName"; '
        'elif [ -f .git/FETCH_HEAD ]; then '
        '    git -c gc.auto=0 checkout -B "$branchName" FETCH_HEAD || git -c gc.auto=0 checkout -f "$branchName"; '
        'else '
        '    git -c gc.auto=0 checkout "$branchName" || git -c gc.auto=0 checkout -f "$branchName"; '
        'fi) && '
        'echo "[GIT] 同步分支最新提交..." && '
        '(git -c gc.auto=0 pull --rebase=false origin "$branchName" 2>/dev/null || git -c gc.auto=0 pull --rebase=false 2>/dev/null || true) && '
        'if [ -f /root/.local/bin/uv ]; then '
        'echo "[UV] 检查并同步 Python 依赖库..." && '
        '/root/.local/bin/uv sync --no-progress; '
        'fi';

    return await runInProot(cmd, onLog: onLog, timeout: const Duration(minutes: 5));
  }

  /// 切换至指定 Release Tag（前置 fetch tags 并同步依赖）
  static Future<ProotExecResult> switchReleaseTag(
    String tagName, {
    Function(String)? onLog,
  }) async {
    if (!isMaiBotGitRepo()) {
      return ProotExecResult(
        success: false,
        exitCode: -1,
        stdout: '',
        stderr: 'MaiBot 仓库不存在',
        output: 'MaiBot 仓库不存在',
      );
    }

    onLog?.call('1. 正在从远端拉取 Release Tag: $tagName (git fetch --tags)...\n');
    final cmd = 'cd $maiBotPath && '
        'git config --global --add safe.directory "*" 2>/dev/null || true; '
        'git config --system --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
        'git config --global --remove-section url."https://ghfast.top/https://github.com/" 2>/dev/null || true; '
        'git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null || true; '
        'echo "[GIT] 抓取标签 $tagName..." && '
        '(git -c gc.auto=0 fetch --tags --force origin 2>/dev/null || '
        'git -c gc.auto=0 fetch origin "refs/tags/$tagName:refs/tags/$tagName" 2>/dev/null || '
        'git -c gc.auto=0 fetch --tags 2>/dev/null || true) && '
        'git stash 2>/dev/null || true; '
        'echo "[GIT] 正在检出 Tag: $tagName..." && '
        '(git -c gc.auto=0 checkout "tags/$tagName" || git -c gc.auto=0 checkout -f "tags/$tagName" || git -c gc.auto=0 checkout "$tagName") && '
        'if [ -f /root/.local/bin/uv ]; then '
        'echo "[UV] 检查并同步 Python 依赖库..." && '
        '/root/.local/bin/uv sync --no-progress; '
        'fi';

    return await runInProot(cmd, onLog: onLog, timeout: const Duration(minutes: 5));
  }
}
