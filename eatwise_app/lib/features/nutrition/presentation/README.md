# features/nutrition/presentation — M4 数据页 UI（/data Tab，PRD M4 / 设计稿 §4.2-③）

- `nutrition_data_page.dart`：页面骨架（日期切换 + H2 总结 + 信号卡/空态 + 专业数据 + 趋势）。
- `date_switcher.dart`：前一天/后一天（不可超今天）/回到今天。
- `signal_cards.dart`：信号灯四卡栅格（auto-fit minmax(150px,1fr)，三重编码）。
- `pro_details.dart`：专业数据折叠区（默认折叠，RDA 参考值〔假设〕待营养背书）。
- `trend_chart.dart`：近 7 日趋势（自绘 CustomPaint 绿描线，零新增依赖）。
