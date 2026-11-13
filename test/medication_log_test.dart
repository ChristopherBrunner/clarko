import 'package:clarko/models/day.dart';
import 'package:clarko/models/dose.dart';
import 'package:clarko/models/medication_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final doses = [
    Dose(id: 'morning', label: 'Morning', hour: 8, minute: 0, tablets: [500]),
    Dose(id: 'night', label: 'Night', hour: 20, minute: 0, tablets: [500]),
  ];

  DateTime day(int offsetFromToday) {
    final now = DateTime(2026, 6, 22, 9);
    return now.subtract(Duration(days: -offsetFromToday));
  }

  // Helper: mark both doses taken on the given date.
  void completeDay(MedicationLog log, DateTime date) {
    log.setTaken('morning', date, true);
    log.setTaken('night', date, true);
  }

  group('streak', () {
    final now = DateTime(2026, 6, 22, 9);

    test('is zero with no log', () {
      expect(MedicationLog.empty().currentStreak(doses, now), 0);
    });

    test('today incomplete does not break a prior streak', () {
      final log = MedicationLog.empty();
      completeDay(log, now.subtract(const Duration(days: 1)));
      completeDay(log, now.subtract(const Duration(days: 2)));
      // Only morning taken today -> today incomplete, streak runs to yesterday.
      log.setTaken('morning', now, true);
      expect(log.currentStreak(doses, now), 2);
    });

    test('counts today when complete', () {
      final log = MedicationLog.empty();
      completeDay(log, now);
      completeDay(log, now.subtract(const Duration(days: 1)));
      expect(log.currentStreak(doses, now), 2);
    });

    test('two missed days in a row stop the count', () {
      final log = MedicationLog.empty();
      completeDay(log, now);
      // skip yesterday and the day before
      completeDay(log, now.subtract(const Duration(days: 3)));
      expect(log.currentStreak(doses, now), 1);
    });

    test('disabled doses are ignored for completeness', () {
      final log = MedicationLog.empty();
      log.setTaken('morning', now, true); // night not taken
      final oneDose = [doses[0], doses[1].copyWith(enabled: false)];
      expect(log.currentStreak(oneDose, now), 1);
    });

    test('counts every calendar day, also across a daylight-saving change', () {
      // 150 complete days ending yesterday (late January to June) span exactly
      // one clock change in any time zone that has DST. Walking back in 24h
      // steps would skip the 23-hour day (or visit the 25-hour day twice) and
      // be off by one. Deliberately not a full year: the two changes cancel.
      final log = MedicationLog.empty();
      for (var i = 1; i <= 150; i++) {
        completeDay(log, DateTime(now.year, now.month, now.day - i));
      }
      expect(log.currentStreak(doses, now), 150);
    });

    test('a new day starts unticked at 03:00 and keeps the streak', () {
      final log = MedicationLog.empty();
      final lastNight = clarkoDay(DateTime(2026, 6, 21, 23, 59));
      final afterMidnight = clarkoDay(DateTime(2026, 6, 22, 2, 59));
      final newDay = clarkoDay(DateTime(2026, 6, 22, 3, 0));
      completeDay(log, lastNight);

      expect(afterMidnight, lastNight, reason: 'still the same Clarko day');
      expect(log.isTaken('night', afterMidnight), isTrue);
      expect(log.isTaken('night', newDay), isFalse);
      expect(log.currentStreak(doses, newDay), 1);
    });
  });

  group('clarko day (03:00 to 03:00)', () {
    test('the small hours belong to the previous day', () {
      expect(clarkoDay(DateTime(2026, 6, 22, 0, 0)), DateTime(2026, 6, 21));
      expect(
          clarkoDay(DateTime(2026, 6, 22, 2, 59, 59)), DateTime(2026, 6, 21));
      expect(clarkoDay(DateTime(2026, 6, 22, 3, 0)), DateTime(2026, 6, 22));
      expect(clarkoDay(DateTime(2026, 6, 22, 23, 59)), DateTime(2026, 6, 22));
      // Across a month boundary.
      expect(clarkoDay(DateTime(2026, 7, 1, 1, 30)), DateTime(2026, 6, 30));
    });

    test('next day start is the coming 03:00', () {
      expect(
          nextDayStart(DateTime(2026, 6, 22, 1, 0)), DateTime(2026, 6, 22, 3));
      expect(
          nextDayStart(DateTime(2026, 6, 22, 3, 0)), DateTime(2026, 6, 23, 3));
      expect(nextDayStart(DateTime(2026, 6, 22, 21, 0)),
          DateTime(2026, 6, 23, 3));
    });
  });

  group('streak safe', () {
    final today = DateTime(2026, 6, 22);
    DateTime ago(int days) =>
        DateTime(today.year, today.month, today.day - days);
    MedicationLog logWith(Iterable<int> completeDaysAgo) {
      final log = MedicationLog.empty();
      for (final d in completeDaysAgo) {
        completeDay(log, ago(d));
      }
      return log;
    }

    test('forgetting yesterday does not reset the streak', () {
      // Today still open, yesterday missed, five full days before that.
      final streak = logWith([2, 3, 4, 5, 6]).streak(doses, today);
      expect(streak.days, 5);
      expect(streak.safeUsed, isTrue);
      expect(streak.safeReady, isFalse);
      expect(streak.rechargeIn, 6);
    });

    test('the missed day is not counted, the days around it are', () {
      final streak = logWith([0, 1, 3, 4]).streak(doses, today);
      expect(streak.days, 4);
      expect(streak.daysSinceSafe, 2);
      expect(streak.rechargeIn, 4);
    });

    test('forgetting two days in a row loses the streak', () {
      expect(logWith([2, 3, 4]).streak(doses, DateTime(2026, 6, 23)).days, 0);
      expect(logWith([3, 4, 5]).streak(doses, today).days, 0);
    });

    test('a second miss too soon after the first ends the streak there', () {
      // complete: today, 1 | miss 2 | complete 3, 4 | miss 5 | complete 6..9
      final streak = logWith([0, 1, 3, 4, 6, 7, 8, 9]).streak(doses, today);
      expect(streak.days, 4, reason: 'only one miss is bridged within a week');
    });

    test('two misses with six full days between them are both bridged', () {
      // complete 0, 1 | miss 2 | complete 3..8 (six days) | miss 9 | complete 10
      final days = [0, 1, 3, 4, 5, 6, 7, 8, 10];
      final streak = logWith(days).streak(doses, today);
      expect(streak.days, 9);
      expect(streak.safeReady, isFalse, reason: 'last used two days ago');
      expect(streak.rechargeIn, 4);
    });

    test('after six full days the safe is ready again', () {
      // complete 0..5 (six days) | miss 6 | complete 7
      final streak = logWith([0, 1, 2, 3, 4, 5, 7]).streak(doses, today);
      expect(streak.days, 7);
      expect(streak.safeUsed, isTrue);
      expect(streak.safeReady, isTrue);
    });

    test('ticking the missed dose late makes the safe unused again', () {
      final log = logWith([2, 3, 4]);
      expect(log.streak(doses, today).safeUsed, isTrue);
      completeDay(log, ago(1)); // e.g. via last night's reminder
      final streak = log.streak(doses, today);
      expect(streak.days, 4);
      expect(streak.safeUsed, isFalse);
      expect(streak.safeReady, isTrue);
    });

    test('a miss before the streak began is not a used safe', () {
      final streak = logWith([1, 2, 3]).streak(doses, today);
      expect(streak.days, 3);
      expect(streak.safeUsed, isFalse);
    });

    test('no streak, no safe', () {
      final streak = MedicationLog.empty().streak(doses, today);
      expect(streak.days, 0);
      expect(streak.safeReady, isFalse);
    });
  });

  test('round-trips through json', () {
    final log = MedicationLog.empty();
    completeDay(log, day(0));
    final restored = MedicationLog.fromJson(log.toJson());
    expect(restored.isTaken('morning', day(0)), isTrue);
    expect(restored.isTaken('night', day(0)), isTrue);
  });

  test('dosage label sums tablets', () {
    final dose =
        Dose(id: 'x', label: 'X', hour: 8, minute: 0, tablets: [500, 250]);
    expect(dose.totalMg, 750);
    expect(dose.dosageLabel, '500mg + 250mg (750mg)');
  });
}
