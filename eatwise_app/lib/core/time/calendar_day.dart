/// Move by calendar dates, preserving UTC/local interpretation and returning
/// midnight. A calendar day can be 23 or 25 hours during daylight-saving changes.
DateTime addCalendarDays(DateTime date, int days) => date.isUtc
    ? DateTime.utc(date.year, date.month, date.day + days)
    : DateTime(date.year, date.month, date.day + days);

/// Difference between date labels, independent of timezone offset changes.
int calendarDaysBetween(DateTime date, DateTime reference) =>
    DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(reference.year, reference.month, reference.day),
        )
        .inDays;
