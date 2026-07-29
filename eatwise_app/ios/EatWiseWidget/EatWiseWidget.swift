//
//  EatWiseWidget.swift
//  EatWiseWidget
//
//  断食计时小组件（《规格-M2 断食计时状态机》§8.1，设计规范 §4.5）。
//
//  数据契约：Dart 侧 WidgetSyncService 经 home_widget 把「状态枚举 + 目标锚点
//  UTC 毫秒 + 本地化文案」写入 App Group `group.com.eatwise.shared` 的
//  UserDefaults（传锚点不传剩余值）；倒计时由 SwiftUI `Text(_:style: .timer)`
//  系统级自治渲染，与 App 内读同一锚点，误差 ≤1 分钟（§8.3）。
//
//  尺寸降级（§4.5）：systemMedium 状态文案 + 倒计时 + 窗口时间段 + 归属日；
//  systemSmall 状态 + 倒计时（优先倒计时）。
//  本 target 需在 Xcode 手工创建并把本目录文件加入，步骤见同目录 README.md。
//

import SwiftUI
import WidgetKit

// MARK: - 共享键（与 Dart 侧 WidgetDataKeys / Android EatWiseWidgetProvider 一致）

private enum WidgetKeys {
    static let appGroupId = "group.com.eatwise.shared"
    static let state = "fasting_state"
    static let anchorMs = "target_anchor_utc_ms"
    static let dueLine = "due_line"
    static let status = "status_label"
    static let noPlan = "no_plan_label"
    static let attribution = "attribution_label"
    static let plan = "plan_label"
    static let window = "eat_window_label"
}

/// 点击深链（Dart WidgetDeepLinkService：home_widget widgetClicked → 首页）。
private let clickUri = URL(string: "eatwise://widget/home")!

// MARK: - Timeline Entry

struct FastingEntry: TimelineEntry {
    let date: Date
    let state: String
    let statusLabel: String
    let targetDate: Date?
    let dueLine: String
    let attributionLabel: String
    let planLabel: String
    let windowLabel: String

    var isFasting: Bool { state == "fasting" || state == "fastingExtended" }
    var isEating: Bool { state == "eating" }
    var isNoPlan: Bool { targetDate == nil }
}

// MARK: - Timeline Provider

struct FastingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry { loadEntry() }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let entry = loadEntry()
        // 锚点到点即状态翻转：预约锚点时刻后刷新一次，保证窗口切换点
        // 状态及时更新（误差 ≤1 分钟由 Dart 触发链 reloadAllTimelines 兜底）。
        let policy: TimelineReloadPolicy = entry.targetDate.map { .after($0) } ?? .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    /// 从 App Group 共享容器读取 Dart 写入的最小数据集（D-18 最小化）。
    private func loadEntry() -> FastingEntry {
        let defaults = UserDefaults(suiteName: WidgetKeys.appGroupId)
        let anchorMs = defaults?.object(forKey: WidgetKeys.anchorMs) as? Double
            ?? (defaults?.object(forKey: WidgetKeys.anchorMs) as? Int).map(Double.init)
        return FastingEntry(
            date: Date(),
            state: defaults?.string(forKey: WidgetKeys.state) ?? "noPlan",
            statusLabel: defaults?.string(forKey: WidgetKeys.status) ?? "",
            targetDate: anchorMs.map { Date(timeIntervalSince1970: $0 / 1000) },
            dueLine: defaults?.string(forKey: WidgetKeys.dueLine) ?? "",
            attributionLabel: defaults?.string(forKey: WidgetKeys.attribution) ?? "",
            planLabel: defaults?.string(forKey: WidgetKeys.plan) ?? "",
            windowLabel: defaults?.string(forKey: WidgetKeys.window) ?? ""
        )
    }
}

// MARK: - Views

struct EatWiseWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FastingEntry

    private var accent: Color {
        // 品牌色（设计 Token：轻盈绿 fasting / 暖阳橙 eating，§2.1）。
        if entry.isEating { return Color(red: 1.0, green: 0.62, blue: 0.27) }
        if entry.isFasting { return Color(red: 0.24, green: 0.75, blue: 0.55) }
        return .primary
    }

    var body: some View {
        switch family {
        case .systemSmall: smallBody
        default: mediumBody
        }
    }

    /// systemSmall（§4.5：状态 + 倒计时，优先倒计时）。
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.isNoPlan ? entry.statusLabel : entry.statusLabel)
                .font(.headline)
                .foregroundStyle(accent)
            if let target = entry.targetDate {
                // 系统级自治倒计时（iOS 14+；锚点制零漂移，§8.1）。
                Text(target, style: .timer)
                    .font(.title2.monospacedDigit().bold())
            } else {
                Text(entry.statusLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }

    /// systemMedium（§4.5：状态 + 倒计时 + 窗口时间段 + 归属日）。
    private var mediumBody: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.statusLabel)
                    .font(.headline)
                    .foregroundStyle(accent)
                if let target = entry.targetDate {
                    Text(target, style: .timer)
                        .font(.largeTitle.monospacedDigit().bold())
                    Text(entry.dueLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text([entry.planLabel, entry.windowLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.attributionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

// MARK: - Widget

struct EatWiseWidget: Widget {
    /// 与 Dart 侧 kWidgetIosKind / home_widget updateWidget(iOSName:) 一致。
    let kind = "EatWiseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingTimelineProvider()) { entry in
            EatWiseWidgetEntryView(entry: entry)
                // 点击进首页（§4.5；与 Android 同一 URI 契约）。
                .widgetURL(clickUri)
        }
        .configurationDisplayName("断食计时")
        .description("在桌面查看断食/进食倒计时与打卡归属日。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct EatWiseWidgetBundle: WidgetBundle {
    var body: some Widget {
        EatWiseWidget()
    }
}
