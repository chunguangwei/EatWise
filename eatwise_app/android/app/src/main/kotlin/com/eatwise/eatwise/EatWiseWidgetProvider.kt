package com.eatwise.eatwise

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 断食计时桌面小组件（《规格-M2 断食计时状态机》§8.2，设计规范 §4.5）。
 *
 * 数据契约：Dart 侧 WidgetSyncService 经 home_widget 把「状态枚举 + 目标锚点
 * UTC 毫秒 + 本地化文案」写入 `HomeWidgetPreferences`（传锚点不传剩余值）；
 * 倒计时由 [android.widget.Chronometer]（countDown）系统侧自治渲染，与 App 内
 * 读同一锚点，误差 ≤1 分钟（§8.3）。
 *
 * 尺寸降级（§4.5）：4×2 状态文案 + Chronometer 倒计时 + 窗口时间段 + 归属日；
 * 2×2 状态 + 「到点时刻」静态文案（倒计时降级）。
 */
class EatWiseWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) {
      updateAppWidget(context, manager, id)
    }
  }

  override fun onAppWidgetOptionsChanged(
      context: Context,
      manager: AppWidgetManager,
      id: Int,
      newOptions: android.os.Bundle?,
  ) {
    // 尺寸变化 → 按 2×2 / 4×2 重选布局（§4.5 信息降级）。
    updateAppWidget(context, manager, id)
  }

  companion object {
    private const val CLICK_URI = "eatwise://widget/home"

    // 与 Dart 侧 WidgetDataKeys 一一对应。
    private const val KEY_STATE = "fasting_state"
    private const val KEY_ANCHOR_MS = "target_anchor_utc_ms"
    private const val KEY_DUE_LINE = "due_line"
    private const val KEY_STATUS = "status_label"
    private const val KEY_NO_PLAN = "no_plan_label"
    private const val KEY_ATTRIBUTION = "attribution_label"
    private const val KEY_PLAN = "plan_label"
    private const val KEY_WINDOW = "eat_window_label"

    // 品牌色（设计 Token：轻盈绿/暖阳橙，§2.1）。
    private const val COLOR_FASTING = 0xFF3DBE8B.toInt()
    private const val COLOR_EATING = 0xFFFF9F45.toInt()
    private const val COLOR_TEXT_PRIMARY = 0xFF1F2937.toInt()
    private const val COLOR_TEXT_SECONDARY = 0xFF6B7280.toInt()

    /** minWidth 达到该值（dp）视为宽版（4×2），否则 2×2 降级布局。 */
    private const val WIDE_MIN_WIDTH_DP = 200

    fun updateAppWidget(context: Context, manager: AppWidgetManager, id: Int) {
      val prefs = HomeWidgetPlugin.getData(context)
      val state = prefs.getString(KEY_STATE, "noPlan") ?: "noPlan"
      val anchorMs = prefs.getLongFlexible(KEY_ANCHOR_MS)

      val options = manager.getAppWidgetOptions(id)
      val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
      val wide = minWidth >= WIDE_MIN_WIDTH_DP
      val views =
          RemoteViews(
              context.packageName,
              if (wide) R.layout.widget_fasting_4x2 else R.layout.widget_fasting_2x2,
          )

      val isNoPlan = state == "noPlan" || anchorMs <= 0L
      val status =
          if (isNoPlan) {
            prefs.getString(KEY_NO_PLAN, "") ?: ""
          } else {
            prefs.getString(KEY_STATUS, "") ?: ""
          }
      views.setTextViewText(R.id.widget_status, status)
      views.setTextColor(
          R.id.widget_status,
          when (state) {
            "eating" -> COLOR_EATING
            "fasting",
            "fastingExtended" -> COLOR_FASTING
            else -> COLOR_TEXT_PRIMARY
          },
      )

      val dueLine = prefs.getString(KEY_DUE_LINE, "") ?: ""
      if (wide) {
        // 4×2：Chronometer 自治倒计时（传锚点不传剩余值，§8）。
        if (!isNoPlan) {
          val base = SystemClock.elapsedRealtime() + (anchorMs - System.currentTimeMillis())
          views.setChronometer(R.id.widget_chronometer, base, null, true)
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            views.setChronometerCountDown(R.id.widget_chronometer, true)
          }
          views.setViewVisibility(R.id.widget_chronometer, View.VISIBLE)
          views.setViewVisibility(R.id.widget_due_line, View.GONE)
        } else {
          views.setViewVisibility(R.id.widget_chronometer, View.GONE)
          views.setTextViewText(R.id.widget_due_line, dueLine)
          views.setViewVisibility(R.id.widget_due_line, View.GONE)
        }
        val plan = prefs.getString(KEY_PLAN, "") ?: ""
        val window = prefs.getString(KEY_WINDOW, "") ?: ""
        views.setTextViewText(
            R.id.widget_window,
            listOf(plan, window).filter { it.isNotEmpty() }.joinToString(" · "),
        )
        views.setTextViewText(
            R.id.widget_attribution,
            if (isNoPlan) "" else prefs.getString(KEY_ATTRIBUTION, "") ?: "",
        )
      } else {
        // 2×2：倒计时降级为「到点时刻」静态文案（§4.5）。
        views.setTextViewText(R.id.widget_due_line, if (isNoPlan) "" else dueLine)
        views.setTextColor(R.id.widget_due_line, COLOR_TEXT_SECONDARY)
      }

      // 点击进首页（§4.5；home_widget 深链 eatwise://widget/home → Dart 路由 '/'）。
      val pendingIntent =
          HomeWidgetLaunchIntent.getActivity(
              context,
              MainActivity::class.java,
              Uri.parse(CLICK_URI),
          )
      views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

      manager.updateAppWidget(id, views)
    }

    /** home_widget 写入的数值按 Dart int 落型（Integer/Long），读取时宽容转换。 */
    private fun SharedPreferences.getLongFlexible(key: String): Long =
        when (val v = all[key]) {
          is Long -> v
          is Int -> v.toLong()
          is Double -> v.toLong()
          is Float -> v.toLong()
          else -> 0L
        }
  }
}
