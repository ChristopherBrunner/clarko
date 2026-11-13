import 'dose.dart';

/// A streak count plus the state of its "streak safe".
class Streak {
  const Streak(this.days, {this.safeUsed = false, this.daysSinceSafe = 0});

  /// Complete days needed after a bridged miss before the safe works again.
  static const rechargeDays = 6;

  /// Number of complete days in the streak.
  final int days;

  /// Whether a missed day inside this streak was bridged.
  final bool safeUsed;

  /// Complete days since that bridged day.
  final int daysSinceSafe;

  /// Whether a missed day right now would be forgiven.
  bool get safeReady => days > 0 && (!safeUsed || daysSinceSafe >= rechargeDays);

  /// Complete days still needed until the safe is ready again.
  int get rechargeIn => safeReady ? 0 : rechargeDays - daysSinceSafe;
}

/// Tracks which doses were taken on which day (a Clarko day, see `day.dart`:
/// callers pass `clarkoDay(now)`, this class only ever deals in dates).
///
/// Stored as a map of `yyyy-mm-dd` -> set of dose ids taken that day. Kept
/// deliberately small; old entries beyond the retention window are pruned.
class MedicationLog {
  MedicationLog(this._taken);

  final Map<String, Set<String>> _taken;

  factory MedicationLog.empty() => MedicationLog({});

  /// Calendar-day key, e.g. "2026-06-22".
  static String dateKey(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  bool isTaken(String doseId, DateTime date) =>
      _taken[dateKey(date)]?.contains(doseId) ?? false;

  void setTaken(String doseId, DateTime date, bool taken) {
    final key = dateKey(date);
    final set = _taken.putIfAbsent(key, () => <String>{});
    if (taken) {
      set.add(doseId);
    } else {
      set.remove(doseId);
      if (set.isEmpty) _taken.remove(key);
    }
  }

  /// Whether every enabled dose was taken on [date].
  bool isDayComplete(List<Dose> doses, DateTime date) {
    final enabled = doses.where((d) => d.enabled).toList();
    if (enabled.isEmpty) return false;
    return enabled.every((d) => isTaken(d.id, date));
  }

  /// Consecutive complete days ending today. Today still counts as "in
  /// progress": if today is not yet complete the streak runs up to yesterday,
  /// so the count never drops just because the day isn't over.
  int currentStreak(List<Dose> doses, DateTime now) => streak(doses, now).days;

  /// The streak ending on the day [today], including the "streak safe": one
  /// missed day is bridged instead of resetting the count (it just doesn't
  /// add to it). Two missed days in a row end the streak, and after a bridged
  /// day it takes [Streak.rechargeDays] complete days before another one can
  /// be bridged.
  ///
  /// Deliberately computed from the log alone, with no stored "safe" state:
  /// if a missed dose is ticked late after all (e.g. from last night's
  /// reminder), the day simply becomes complete and the safe is unused again.
  /// `ClarkoStore.streak` in Kotlin mirrors this walk for the widget.
  Streak streak(List<Dose> doses, DateTime today) {
    var days = isDayComplete(doses, today) ? 1 : 0;
    var run = days; // complete days since the last bridged miss
    var pendingMiss = false; // a missed day that an older complete day may bridge
    var safeUsed = false;
    var daysSinceSafe = 0;

    var cursor = _dayBefore(today);
    for (var i = 0; i < 4000; i++) {
      if (isDayComplete(doses, cursor)) {
        if (pendingMiss) {
          if (!safeUsed) daysSinceSafe = run;
          safeUsed = true;
          pendingMiss = false;
          run = 0;
        }
        days++;
        run++;
      } else {
        // Two misses in a row, or a second miss too soon after a bridged one.
        if (pendingMiss || (safeUsed && run < Streak.rechargeDays)) break;
        pendingMiss = true;
      }
      cursor = _dayBefore(cursor);
    }
    return Streak(days, safeUsed: safeUsed, daysSinceSafe: daysSinceSafe);
  }

  /// The previous calendar day. Deliberately not `subtract(Duration(days: 1))`:
  /// that goes back 24 hours, which skips a whole date when the walk crosses a
  /// daylight-saving change (the day the clocks go forward is only 23h long).
  static DateTime _dayBefore(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);

  /// Drop entries older than [keepDays] to bound storage size.
  void prune(DateTime now, {int keepDays = 400}) {
    final cutoff = DateTime(now.year, now.month, now.day - keepDays);
    _taken.removeWhere((key, _) {
      final parts = key.split('-').map(int.parse).toList();
      final date = DateTime(parts[0], parts[1], parts[2]);
      return date.isBefore(cutoff);
    });
  }

  Map<String, dynamic> toJson() =>
      _taken.map((key, value) => MapEntry(key, value.toList()));

  factory MedicationLog.fromJson(Map<String, dynamic> json) {
    final map = <String, Set<String>>{};
    json.forEach((key, value) {
      map[key] = (value as List).map((e) => e as String).toSet();
    });
    return MedicationLog(map);
  }
}
