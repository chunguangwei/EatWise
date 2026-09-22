/// 时区启动装配与设备时区统一读取口径（D-07：UTC 存储本地渲染）。
///
/// 关键坑（真机走查「记录全默认早餐」根因）：timezone 包
/// `initializeDatabase` 末尾会显式 `setLocalLocation(UTC)`，`tz.local`
/// 保持 UTC 直到显式 set——曾只装载不设置，餐次智能预判/归属日全按
/// UTC 小时算（北京 13:00 = 05:00 UTC → 误判早餐，00:00–07:59 的记录
/// 归属前一天），X-Timezone 头也误报 UTC（生产 Caddy 日志实锤
/// `X-Timezone: Etc/UTC`）。
///
/// 设备 IANA 名无免依赖 API（flutter_timezone 会新增原生 pod，按仓库
/// 约定需 pod install + 真机构建验证），用 offset 匹配替代：中国为上架
/// 主区，同偏移命中优先取 Asia/Shanghai（避开同偏移 DST 干扰项）；无
/// 命中回落 Asia/Shanghai → UTC。夏令时歧义（同偏移多时区取其一）对
/// 归属日/餐次口径无影响（偏移相同即本地小时相同）。
///
/// 两条分支都必须 setLocalLocation：timezone 包 `_local` 是 `late` 无
/// 默认值，装载失败时若不设置，之后任何 `tz.local` 读直接
/// LateInitializationError（旧 main 注释宣称的「回退 UTC 防御」并不存在）。
library;

import 'dart:typed_data';

import 'package:timezone/timezone.dart' as tz;

/// [bootstrapTimezone] 是否已执行。测试进程不跑 main()，此标志恒 false，
/// [deviceLocationFallback] 保持旧「硬编码 Asia/Shanghai」口径——既有
/// 测试（widget 冒烟/营养目标等按上海时区写死断言）行为不变；生产
/// 启动后走真实设备时区。
bool _bootstrapDone = false;

/// 装载时区数据并把 `tz.local` 设为设备时区；任何一步失败均回落 UTC
/// （绝不遗留未初始化状态）。[tzfData] 为 null（资产缺失）时同样回落。
void bootstrapTimezone(Uint8List? tzfData) {
  try {
    if (tzfData == null) throw StateError('tzf asset missing');
    tz.initializeDatabase(tzfData);
    tz.setLocalLocation(_matchDeviceLocation());
  } on Object {
    try {
      tz.setLocalLocation(tz.UTC);
    } on Object {
      // 连 UTC 都设不上（不可能路径）：交由消费方 fallback 兜底。
    }
  }
  _bootstrapDone = true;
}

/// 设备时区的统一读取口径（deviceLocationProvider / 各仓储默认值共用）。
/// 未装配（纯单测/预览）回退 Asia/Shanghai（〔假设〕MVP 上架中国区，
/// 与历史口径一致）；时区库缺失再回 UTC。
tz.Location deviceLocationFallback() {
  if (_bootstrapDone) {
    try {
      return tz.local;
    } on Object {
      return tz.UTC;
    }
  }
  try {
    return tz.getLocation('Asia/Shanghai');
  } on Object {
    return tz.UTC;
  }
}

tz.Location _matchDeviceLocation() {
  final deviceOffset = DateTime.now().timeZoneOffset;
  Duration offsetOf(tz.Location location) =>
      tz.TZDateTime.now(location).timeZoneOffset;
  try {
    final shanghai = tz.getLocation('Asia/Shanghai');
    if (offsetOf(shanghai) == deviceOffset) return shanghai;
  } on Object {
    // 数据文件缺表等异常：走下方通用匹配。
  }
  final matches = tz.timeZoneDatabase.locations.values
      .where((l) => offsetOf(l) == deviceOffset)
      .toList();
  if (matches.isNotEmpty) return matches.first;
  try {
    return tz.getLocation('Asia/Shanghai');
  } on Object {
    return tz.UTC;
  }
}
