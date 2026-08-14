import 'dart:io';

import 'package:global_repository/global_repository.dart';

import '../utils/file_utils.dart';

/// 环境引导器：负责将动态库链接到数据目录、创建 busybox 软链接。
class EnvBootstrapper {
  static final _libSoRegExp = RegExp(r'^lib|\.so$');

  /// 初始化环境，将动态库中的文件链接到数据目录
  /// Init environment and link files from the dynamic library to the data directory
  static Future<void> initEnvir() async {
    await Directory(RuntimeEnvir.binPath).create(recursive: true);
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so'
    ];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      // when android target sdk > 28
      // cannot execute file in /data/data/com.xxx/files/usr/bin
      // so we need create a link to /data/data/com.xxx/files/usr/bin
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(_libSoRegExp, '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      // custom path, termux-api will invoke
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        // old version adb is plain file
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
      if (await link.exists()) {
        try {
          await link.delete();
        } catch (e) {
          Log.e('delete link error -> $e');
        }
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        await link.create(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }

    // 处理 busybox 相关的符号链接，确保 proot 依赖的命令可用
    await createBusyboxLink();
  }

  /// 创建 busybox 的软连接，来确保 proot 会用到的命令正常运行
  /// create busybox symlinks, to ensure proot can use the commands normally
  static Future<void> createBusyboxLink() async {
    try {
      List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip'
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd'
        ]
      ];

      for (String linkName in links) {
        String linkPath = '${RuntimeEnvir.binPath}/$linkName';
        Link link = Link(linkPath);
        if (await link.exists()) {
          try {
            await link.delete();
          } catch (e) {
            Log.e('delete busybox link error -> $e');
          }
        }
        try {
          await link.create('${RuntimeEnvir.binPath}/busybox');
        } catch (e) {
          Log.e('create busybox link error -> $e');
        }
      }

      String fileLinkPath = '${RuntimeEnvir.binPath}/file';
      Link fileLink = Link(fileLinkPath);
      if (await fileLink.exists()) {
        try {
          await fileLink.delete();
        } catch (e) {
          Log.e('delete file link error -> $e');
        }
      }
      try {
        await fileLink.create('/system/bin/file');
      } catch (e) {
        Log.e('create file link error -> $e');
      }
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }
}
