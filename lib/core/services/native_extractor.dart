import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:ffi/ffi.dart';
import 'package:global_repository/global_repository.dart';

typedef ChmodC = Int32 Function(Pointer<Utf8> path, Uint32 mode);
typedef ChmodDart = int Function(Pointer<Utf8> path, int mode);

class NativeExtractor {
  static void extractTarXz(String archivePath, String outputPath) {
    Log.i('开始原生解压 $archivePath 到 $outputPath', 'NativeExtractor');

    // 1. 读取 XZ 并解码为 Tar 字节 (对于 60MB 文件，会消耗几百MB内存，放在 Isolate 是安全的)
    final bytes = File(archivePath).readAsBytesSync();
    final tarBytes = XZDecoder().decodeBytes(bytes);

    // 2. 解码 Tar 文件
    final archive = TarDecoder().decodeBytes(tarBytes);

    final symbolicLinks = <ArchiveFile>[];
    
    // libc chmod bound via FFI
    final dylib = DynamicLibrary.process();
    final chmod = dylib.lookupFunction<ChmodC, ChmodDart>('chmod');

    // 3. 第一阶段：提取普通文件和目录
    for (final file in archive) {
      if (file.isSymbolicLink) {
        symbolicLinks.add(file);
        continue;
      }

      final outPath = '$outputPath/${file.name}';
      
      if (file.isFile) {
        final outputStream = OutputFileStream(outPath);
        file.writeContent(outputStream);
        outputStream.closeSync();

        // 还原 POSIX 文件权限 (如果包含可执行位)
        final mode = file.mode;
        // mode 是 10 进制的 POSIX 权限表示，例如 33261 (0100755)
        // 提取低 9 位权限 (rwxrwxrwx)
        final filePermission = mode & 0x1FF;
        if (filePermission > 0) {
          final ptr = outPath.toNativeUtf8();
          try {
            chmod(ptr, filePermission);
          } finally {
            calloc.free(ptr);
          }
        }
      } else {
        Directory(outPath).createSync(recursive: true);
        
        final mode = file.mode;
        final filePermission = mode & 0x1FF;
        if (filePermission > 0) {
          final ptr = outPath.toNativeUtf8();
          try {
            chmod(ptr, filePermission);
          } finally {
            calloc.free(ptr);
          }
        }
      }
    }

    // 4. 第二阶段：处理所有 Symlink
    for (final entity in symbolicLinks) {
      final linkPath = '$outputPath/${entity.name}';
      final link = Link(linkPath);
      try {
        link.createSync(entity.nameOfLinkedFile, recursive: true);
      } catch (e) {
        Log.w('软连接创建失败 [$linkPath -> ${entity.nameOfLinkedFile}]: $e', 'NativeExtractor');
      }
    }
    
    Log.i('原生解压完成！', 'NativeExtractor');
  }
}
