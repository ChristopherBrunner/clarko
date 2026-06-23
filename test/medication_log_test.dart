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

    test('a gap stops the count', () {
      final log = MedicationLog.empty();
      completeDay(log, now);
      // skip yesterday
      completeDay(log, now.subtract(const Duration(days: 2)));
      expect(log.currentStreak(doses, now), 1);
    });

    test('disabled doses are ignored for completeness', () {
      final log = MedicationLog.empty();
      log.setTaken('morning', now, true); // night not taken
      final oneDose = [doses[0], doses[1].copyWith(enabled: false)];
      expect(log.currentStreak(oneDose, now), 1);
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
