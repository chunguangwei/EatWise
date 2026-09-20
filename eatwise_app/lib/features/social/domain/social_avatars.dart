import 'package:flutter/material.dart';

/// 预设默认头像库（微信/QQ 式：纯色圆底 + 白色图标，零资源文件）。
///
/// 索引即 `avatarId`（服务端 posts.avatarId 存的就是这里的下标，0..7）：
/// 发帖时选定即固定跟帖，不随用户资料变。客户端渲染与服务端校验共用
/// 本表长度（服务端 DTO `@Max(7)` 与此一致，改这里必须同步 DTO）。
final class SocialAvatar {
  const SocialAvatar({
    required this.background,
    required this.icon,
    required this.labelZh,
    required this.labelEn,
  });

  final Color background;
  final IconData icon;

  /// 头像选择弹层的语义标签（按 locale 取）。
  final String labelZh;
  final String labelEn;
}

const List<SocialAvatar> kSocialAvatars = <SocialAvatar>[
  SocialAvatar(
    background: Color(0xFF66BB6A),
    icon: Icons.eco_outlined,
    labelZh: '青草',
    labelEn: 'Leaf',
  ),
  SocialAvatar(
    background: Color(0xFFFFA726),
    icon: Icons.local_fire_department_outlined,
    labelZh: '火焰',
    labelEn: 'Flame',
  ),
  SocialAvatar(
    background: Color(0xFF42A5F5),
    icon: Icons.water_drop_outlined,
    labelZh: '水滴',
    labelEn: 'Drop',
  ),
  SocialAvatar(
    background: Color(0xFFAB47BC),
    icon: Icons.self_improvement,
    labelZh: '静坐',
    labelEn: 'Zen',
  ),
  SocialAvatar(
    background: Color(0xFFEF5350),
    icon: Icons.volunteer_activism,
    labelZh: '爱心',
    labelEn: 'Heart',
  ),
  SocialAvatar(
    background: Color(0xFF5C6BC0),
    icon: Icons.nightlight_outlined,
    labelZh: '夜灯',
    labelEn: 'Moon',
  ),
  SocialAvatar(
    background: Color(0xFF26A69A),
    icon: Icons.spa_outlined,
    labelZh: '荷叶',
    labelEn: 'Spa',
  ),
  SocialAvatar(
    background: Color(0xFF8D6E63),
    icon: Icons.bakery_dining_outlined,
    labelZh: '面包',
    labelEn: 'Bread',
  ),
];

/// 越界/缺失索引回落首项（服务端已 `@Min(0) @Max(7)` 校验，这里只兜历史脏数据）。
SocialAvatar socialAvatarOf(int? id) {
  if (id == null || id < 0 || id >= kSocialAvatars.length) {
    return kSocialAvatars.first;
  }
  return kSocialAvatars[id];
}
