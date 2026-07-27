import 'dart:convert';
import 'dart:io';

import 'package:timezone/timezone.dart' as tz;

/// 测试用时区数据库初始化。
///
/// flutter test 环境不支持 `Isolate.resolvePackageUriSync`
/// （`package:timezone/standalone.dart` 的默认初始化路径），
/// 这里经 `.dart_tool/package_config.json` 手动定位数据文件。
Future<void> initTestTimeZones() async {
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = (config['packages']! as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final tzPackage = packages.firstWhere((p) => p['name'] == 'timezone');
  var rootUri = Uri.parse(tzPackage['rootUri']! as String);
  // rootUri 可能无尾部斜杠，resolve 时会吃掉最后一段，先补齐
  if (!rootUri.path.endsWith('/')) {
    rootUri = rootUri.replace(path: '${rootUri.path}/');
  }
  final packageUri = Uri.parse(tzPackage['packageUri']! as String);
  final dataUri = rootUri.resolveUri(packageUri).resolve('data/latest_all.tzf');
  final bytes = await File.fromUri(dataUri).readAsBytes();
  tz.initializeDatabase(bytes);
}
