import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// record 命名空间 i18n 校验（D-15：中英双语 key 一一对应且非空）。
///
/// 集成说明：record/onboarding/notify 命名空间已深合并进统一的
/// `i18n/strings_*.i18n.json`（slang `namespaces: false`），本测试从合并后
/// 文件中提取 `record.*` 子树做一致性校验。
void main() {
  Map<String, String> flatten(Map<String, dynamic> json, [String prefix = '']) {
    final out = <String, String>{};
    for (final entry in json.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        out.addAll(flatten(value, key));
      } else {
        out[key] = value as String;
      }
    }
    return out;
  }

  Map<String, String> recordKeysOf(Map<String, String> flat) {
    return Map<String, String>.fromEntries(
      flat.entries.where((e) => e.key.startsWith('record.')),
    );
  }

  test('record 命名空间中英 key 集合一致且均非空', () async {
    final zh = recordKeysOf(
      flatten(
        jsonDecode(await File('i18n/strings_zh-CN.i18n.json').readAsString())
            as Map<String, dynamic>,
      ),
    );
    final en = recordKeysOf(
      flatten(
        jsonDecode(await File('i18n/strings_en.i18n.json').readAsString())
            as Map<String, dynamic>,
      ),
    );
    expect(zh, isNotEmpty, reason: '合并后的 strings 文件缺少 record.* key');
    expect(zh.keys.toSet(), en.keys.toSet());
    for (final entry in zh.entries) {
      expect(entry.value, isNotEmpty, reason: 'zh 空翻译: ${entry.key}');
    }
    for (final entry in en.entries) {
      expect(entry.value, isNotEmpty, reason: 'en 空翻译: ${entry.key}');
    }
  });
}
