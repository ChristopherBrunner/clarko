/// Clarko's day does not end at midnight but at 03:00: a night dose taken (and
/// ticked) a little after midnight still belongs to the day that is ending.
///
/// Everything that asks "which day is it?" goes through [clarkoDay] — the app,
/// the reminder handler, and (mirrored in `ClarkoStore.kt`) the home widget —
/// so they can never disagree about it.
const dayStartHour = 3;

/// The Clarko day (a date at 00:00) that [moment] belongs to. Compares the
/// wall-clock hour rather than subtracting three hours, so it stays correct on
/// the nights the clocks change.
DateTime clarkoDay(DateTime moment) => DateTime(
      moment.year,
      moment.month,
      moment.hour < dayStartHour ? moment.day - 1 : moment.day,
    );

/// The next moment a new Clarko day starts after [now].
DateTime nextDayStart(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, dayStartHour);
  return today.isAfter(now)
      ? today
      : DateTime(now.year, now.month, now.day + 1, dayStartHour);
}
