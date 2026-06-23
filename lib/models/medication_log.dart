import 'dose.dart';

/// Tracks which doses were taken on which calendar day.
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
  int currentStreak(List<Dose> doses, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var streak = 0;
    var cursor = today;

    if (isDayComplete(doses, today)) {
      streak = 1;
      cursor = today.subtract(const Duration(days: 1));
    } else {
      cursor = today.subtract(const Duration(days: 1));
    }

    while (isDayComplete(doses, cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Drop entries older than [keepDays] to bound storage size.
  void prune(DateTime now, {int keepDays = 400}) {
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: keepDays));
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
