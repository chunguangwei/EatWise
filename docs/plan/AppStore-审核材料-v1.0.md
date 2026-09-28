# App Store 审核材料包（v1.0，2026-09-28）

> 上架范围：海外非欧盟 + 港澳台。构建版本：v1.13.26+90（提审包必须带 `--dart-define=API_BASE_URL=https://wcg.polin.tech:8443/v1`）。
> 本文所有英文段落均可直接复制进 App Store Connect。

## 1. 审核演示账号（App Review Information → Sign-in required）

- Username: `appreview`
- Password: `Review#2026EatWise`
- 已在生产环境预建（2026-09-28，用户 id `5813104d-7bde-4bb2-8b23-fa5393167471`）。

## 2. Review Notes（直接粘贴）

```
Demo account (username / password): appreview / Review#2026EatWise
Phone-number sign-in is intentionally disabled in this release; please use the provided account.

Notes for review:
1. AI features (photo / voice / barcode food recognition) run 100% on-device via an OPTIONAL ~2.4GB model download (Gemma). A confirmation sheet with size and license terms is shown before downloading. All core features work without the model — manual search and logging are always available. No photo or audio ever leaves the device for AI processing.
2. Apple Health data (steps / active energy / weight) is read-only, displayed and aggregated on-device only, never uploaded or shared.
3. Community posts are pre-moderated before publishing, can be reported in-app, and users can block other users (post card menu → Block; manage in Settings → Privacy → Blocked Users).
4. Account deletion: Settings → Account → Delete Account. The request takes effect immediately (all sessions revoked, data frozen); records are permanently erased after a 7-day cooling-off period shown to the user, during which deletion can be cancelled with one tap.
5. Fasting content includes a pre-start screening for contraindicated groups (minors, pregnancy/breastfeeding, eating-disorder history, diabetes, etc.), an age confirmation (13+) during onboarding, and persistent "not medical advice" disclaimers.
6. Notifications are local only (fasting / hydration reminders); no remote push is used.
7. Contact: chunguangwee@gmail.com
```

## 3. App Store Connect 元数据

### 3.1 URLs

- Privacy Policy URL: `https://wcg.polin.tech:8443/privacy`
- User Agreement（如问卷需要）: `https://wcg.polin.tech:8443/terms`
- Support URL: `https://wcg.polin.tech:8443/privacy`（含联系方式；后续可换独立支持页）
- Marketing URL:（可选，留空）

⚠️ 自签名证书：审核系统抓取 URL 一般不做证书链严格校验，历史案例可过；若被驳回「URL 不可达」，备选方案是把这两页挂到 GitHub Pages（仓库 public，docs/ 目录即可开）。

### 3.2 关键词（Keywords，100 字符内，逗号分隔不带空格）

```
fasting,intermittent,16:8,diet,calorie,food,tracker,weight,health,AI,photo,scan,nutrition
```

### 3.3 描述（Description）

**English:**

```
EatWise — Intermittent Fasting & Smart Food Logging

Build a healthier rhythm with intermittent fasting and effortless food tracking.

FASTING, YOUR WAY
• Popular plans (16:8, 18:6, 20:4) with customizable eating windows
• Live fasting timer with gentle milestone reminders
• Streaks and make-up cards to keep you motivated

LOG FOOD IN SECONDS
• Photo recognition: snap a meal, AI identifies each dish and estimates portions — entirely on your device
• Voice logging, barcode scanning, and a bilingual food database (Chinese Food Composition Tables + USDA)
• Water, weight, steps and exercise tracking in one place

CLEAR NUTRITION INSIGHTS
• Calorie budget with traffic-light signals for protein, carbs and fat
• 7-day trends and daily summaries

PRIVATE BY DESIGN
• On-device AI: your photos and voice never leave your phone
• Read-only Apple Health integration — data stays on your device
• No ads, no tracking

EatWise provides general wellness information and is not medical advice. Fasting is not recommended for minors, pregnant or breastfeeding women, or people with a history of eating disorders. Please consult a professional if in doubt.
```

**繁體中文（港澳台）：**

```
EatWise — 輕斷食與智慧飲食記錄

用輕斷食和輕鬆的飲食記錄，建立更健康的節奏。

斷食，照你的方式
• 熱門方案（16:8、18:6、20:4）與自訂進食窗口
• 即時斷食計時與里程碑提醒
• 連勝與補簽卡，陪你堅持

幾秒完成記錄
• 拍照識別：AI 辨識每餐內容並估算份量——全程在你的裝置上完成
• 語音記錄、掃碼記錄，中英雙語食物資料庫（中國食物成分表 + USDA）
• 飲水、體重、步數與運動一站記錄

清楚的營養洞察
• 熱量預算與蛋白質/碳水/脂肪信號燈
• 近 7 日趨勢與每日總結

隱私優先
• 端側 AI：照片與語音不離開你的手機
• Apple 健康唯讀整合——資料只留在裝置上
• 無廣告、無追蹤

EatWise 提供一般健康資訊，不構成醫療建議。未成年人、孕期哺乳期女性、有進食障礙史者不建議斷食，如有疑問請諮詢專業人士。
```

### 3.4 Promotional Text（170 字符，可不改二进制随时更新）

```
Snap a photo and let on-device AI log your meal. Fasting timer, calorie signals and trends — private by design, no ads.
```

## 4. 年龄分级问卷（Age Rating）

| 题目 | 回答 |
|---|---|
| Medical or Treatment Information | Infrequent/Mild |
| Mature/Suggestive Themes（UGC 社区） | Infrequent/Mild |
| Unrestricted Web Access | No |
| 其余全部 | None |

→ 预期分级 **12+**。

## 5. 隐私营养标签（App Privacy）

| 类别 | 数据项 | Linked to User | 用途 |
|---|---|---|---|
| Health & Fitness | Health（身高/体重/饮食/断食/饮水/运动记录） | Yes | App Functionality |
| Identifiers | User ID | Yes | App Functionality |
| User Content | Photos or Videos、Other User Content（社区帖） | Yes | App Functionality |
| Usage Data | Product Interaction（匿名化埋点） | Yes（保守口径） | Analytics |
| 不申报 | 手机号（通道未启用）、HealthKit（不出端）、崩溃（无 SDK）、位置、通讯录 | — | — |
| Tracking | **No**（无 IDFA/广告） | — | — |

## 6. 其他问卷

- **出口合规**：已在 Info.plist 置 `ITSAppUsesNonExemptEncryption=false` —— 提审不再询问；
- **AI 内容申报**：Yes — 内容生成类 AI；补充说明：on-device only、optional download、user-confirmed estimates、core features work without it；
- **内容版权**：No third-party content（食物数据来源 CFCT+USDA 已在 App 内公示）；
- **广告**：No ads。

## 7. 截图清单（必交）

- 6.7"（iPhone 15 Pro Max 等）：5 张建议 = 首页断食计时 / 记录页（拍照识别）/ 食物详情信号灯 / 数据趋势 / 社区；
- 6.5"（如有需要同套）；iPad 截图（因 family 含 iPad + UIRequiresFullScreen）；
- 截英文与繁中各一套（港澳台 storefront 用繁中）。

## 8. 提审前最后一查

1. `flutter build ipa --release --dart-define=API_BASE_URL=https://wcg.polin.tech:8443/v1`（漏了审核员全站网络失败，已踩两次）；
2. 用演示账号在 TestFlight 包上完整走一遍：注册引导（含 13 岁确认）→ 断食计时 → 拍照/搜索记录 → 社区发帖/举报/屏蔽 → 设置各页 → 删除账号；
3. 确认生产服务端为最新（含 user_blocks migration 与 /privacy /terms）；
4. Xcode Organizer 上传后检查无 ITMS 警告（90683 已兜底）。
