import 'package:flutter/material.dart';

/// 预设默认头像库（微信/QQ 式：纯色圆底 + 白色图标，零资源文件）。
///
/// 索引即 `avatarId`（服务端 posts.avatarId 存的就是这里的下标）：
/// 发帖时选定即固定跟帖，不随用户资料变。**只追加、不重排/删除**——
/// 存量匿名帖按当天下标渲染，挪位会让它们的头像漂移。
/// 服务端 DTO 宽松收 0..63（`social.dto.ts @Max(63)`），本表为权威：
/// 加头像只改这里（客户端自更新），不必追服务端；老客户端遇到越界
/// 下标由 [socialAvatarOf] 回落首项。
final class SocialAvatar {
  const SocialAvatar({required this.background, required this.icon});

  final Color background;
  final IconData icon;
}

const List<SocialAvatar> kSocialAvatars = <SocialAvatar>[
  // ——— 基础（v1.12.7 首发 8 款，下标 0–7 勿动）———
  SocialAvatar(background: Color(0xFF66BB6A), icon: Icons.eco_outlined), // 0 青草
  SocialAvatar(
    background: Color(0xFFFFA726),
    icon: Icons.local_fire_department_outlined,
  ), // 1 火焰
  SocialAvatar(
    background: Color(0xFF42A5F5),
    icon: Icons.water_drop_outlined,
  ), // 2 水滴
  SocialAvatar(
    background: Color(0xFFAB47BC),
    icon: Icons.self_improvement,
  ), // 3 静坐
  SocialAvatar(
    background: Color(0xFFEF5350),
    icon: Icons.volunteer_activism,
  ), // 4 爱心
  SocialAvatar(
    background: Color(0xFF5C6BC0),
    icon: Icons.nightlight_outlined,
  ), // 5 夜灯
  SocialAvatar(background: Color(0xFF26A69A), icon: Icons.spa_outlined), // 6 荷叶
  SocialAvatar(
    background: Color(0xFF8D6E63),
    icon: Icons.bakery_dining_outlined,
  ), // 7 面包
  // ——— 动物 ———
  SocialAvatar(background: Color(0xFFEC407A), icon: Icons.pets), // 8 猫爪
  SocialAvatar(background: Color(0xFF29B6F6), icon: Icons.flutter_dash), // 9 小鸟
  SocialAvatar(background: Color(0xFF9E9D24), icon: Icons.bug_report), // 10 小虫
  // ——— 植物 ———
  SocialAvatar(
    background: Color(0xFFD81B60),
    icon: Icons.local_florist,
  ), // 11 玫瑰
  SocialAvatar(
    background: Color(0xFF7CB342),
    icon: Icons.emoji_nature_outlined,
  ), // 12 花花
  SocialAvatar(
    background: Color(0xFF2E7D32),
    icon: Icons.forest_outlined,
  ), // 13 森林
  SocialAvatar(
    background: Color(0xFF43A047),
    icon: Icons.nature_people_outlined,
  ), // 14 树下
  SocialAvatar(
    background: Color(0xFF00897B),
    icon: Icons.park_outlined,
  ), // 15 公园
  SocialAvatar(background: Color(0xFF558B2F), icon: Icons.grass), // 16 草坪
  SocialAvatar(
    background: Color(0xFFC0CA33),
    icon: Icons.yard_outlined,
  ), // 17 盆栽
  // ——— 五谷蔬果 ———
  SocialAvatar(
    background: Color(0xFFF9A825),
    icon: Icons.agriculture_outlined,
  ), // 18 麦穗
  SocialAvatar(
    background: Color(0xFFFB8C00),
    icon: Icons.ramen_dining_outlined,
  ), // 19 拉面
  SocialAvatar(
    background: Color(0xFFA1887F),
    icon: Icons.rice_bowl_outlined,
  ), // 20 米饭
  SocialAvatar(
    background: Color(0xFF7E57C2),
    icon: Icons.soup_kitchen_outlined,
  ), // 21 热汤
  SocialAvatar(
    background: Color(0xFFFFB74D),
    icon: Icons.breakfast_dining_outlined,
  ), // 22 早餐
  // ——— 冰饮甜点 ———
  SocialAvatar(
    background: Color(0xFFF48FB1),
    icon: Icons.icecream_outlined,
  ), // 23 甜筒
  SocialAvatar(
    background: Color(0xFF4DD0E1),
    icon: Icons.emoji_food_beverage_outlined,
  ), // 24 气泡饮
];

/// 越界/缺失索引回落首项（服务端宽松收 0..63，老客户端遇到新版下标走这里）。
SocialAvatar socialAvatarOf(int? id) {
  if (id == null || id < 0 || id >= kSocialAvatars.length) {
    return kSocialAvatars.first;
  }
  return kSocialAvatars[id];
}
