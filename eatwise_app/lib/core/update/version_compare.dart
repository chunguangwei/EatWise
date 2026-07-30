/// 语义化版本比较（x.y.z[+build]，容忍前导 v；build 元数据不参与比较，
/// 与服务端 semver.util 口径一致）。
library;

/// 解析结果（build 不含 `+`，缺省为 null）。
final class AppVersionParts {
  const AppVersionParts(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final String? build;
}

final RegExp _versionPattern = RegExp(
  r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+([0-9A-Za-z.-]+))?$',
);

/// 解析版本号；非法输入抛 [FormatException]。
AppVersionParts parseAppVersion(String version) {
  final text = version.trim();
  final stripped = text.startsWith('v') || text.startsWith('V')
      ? text.substring(1)
      : text;
  final match = _versionPattern.firstMatch(stripped);
  if (match == null) {
    throw FormatException('非法语义化版本号: $version');
  }
  return AppVersionParts(
    int.parse(match.group(1)!),
    match.group(2) == null ? 0 : int.parse(match.group(2)!),
    match.group(3) == null ? 0 : int.parse(match.group(3)!),
    match.group(4),
  );
}

/// 比较两个版本号：a < b 返回负数，相等返回 0，a > b 返回正数。
int compareAppVersions(String a, String b) {
  final pa = parseAppVersion(a);
  final pb = parseAppVersion(b);
  if (pa.major != pb.major) return pa.major - pb.major;
  if (pa.minor != pb.minor) return pa.minor - pb.minor;
  return pa.patch - pb.patch;
}
