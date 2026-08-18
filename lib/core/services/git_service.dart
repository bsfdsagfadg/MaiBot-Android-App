import 'dart:io';

import '../constants/scripts.dart' as scripts;
import 'proot_runner.dart';

export 'proot_runner.dart' show ProotExecResult;
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
    return await ProotRunner.runCommand(
      command,
      onLog: onLog,
      timeout: timeout,
      workingDir: maiBotPath,
    );
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
