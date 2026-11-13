import 'package:clarko/models/dose.dart';
import 'package:clarko/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final morning =
      Dose(id: 'morning', label: 'Morning', hour: 8, minute: 0, tablets: [500]);
  final afternoon =
      Dose(id: 'noon', label: 'Afternoon', hour: 14, minute: 0, tablets: [500]);
  final night = Dose(
      id: 'night', label: 'Night', hour: 20, minute: 0, tablets: [500, 250]);

  group('reminderDay (which day a "Mark as taken" tap counts for)', () {
    final today = DateTime(2026, 6, 22);
    final yesterday = DateTime(2026, 6, 21);

    test('same evening counts for today', () {
      expect(night.reminderDay(DateTime(2026, 6, 22, 20, 0)), today);
      expect(night.reminderDay(DateTime(2026, 6, 22, 23, 59)), today);
    });

    test("last night's reminder answered after midnight counts for yesterday",
        () {
      expect(night.reminderDay(DateTime(2026, 6, 22, 0, 10)), yesterday);
      expect(night.reminderDay(DateTime(2026, 6, 22, 7, 59)), yesterday);
      expect(afternoon.reminderDay(DateTime(2026, 6, 22, 1, 0)), yesterday);
    });

    test('a reminder older than 12 hours is about today', () {
      expect(night.reminderDay(DateTime(2026, 6, 22, 8, 0)), today);
      expect(night.reminderDay(DateTime(2026, 6, 22, 19, 30)), today);
      // Yesterday morning's leftover reminder, used to log today's dose early.
      expect(morning.reminderDay(DateTime(2026, 6, 22, 7, 30)), today);
    });

    test('respects the 03:00 day start', () {
      // 02:30: still yesterday's Clarko day, whatever the reminder's age.
      expect(night.reminderDay(DateTime(2026, 6, 22, 2, 30)), yesterday);
      expect(morning.reminderDay(DateTime(2026, 6, 22, 2, 30)), yesterday);
      // 04:00, new day has begun, but last night's reminder is only 8h old.
      expect(night.reminderDay(DateTime(2026, 6, 22, 4, 0)), yesterday);
      // A dose scheduled in the small hours belongs to the day that is ending.
      final late =
          Dose(id: 'late', label: 'Late', hour: 1, minute: 0, tablets: [500]);
      expect(late.reminderDay(DateTime(2026, 6, 22, 1, 5)), yesterday);
      expect(late.reminderDay(DateTime(2026, 6, 22, 3, 30)), yesterday);
      expect(late.reminderDay(DateTime(2026, 6, 22, 14, 0)), today);
    });

    test('after the reminder time it is always today', () {
      expect(morning.reminderDay(DateTime(2026, 6, 22, 8, 0)), today);
      expect(morning.reminderDay(DateTime(2026, 6, 22, 23, 0)), today);
    });
  });

  group('reminder text', () {
    test('uses a sun for daytime and a moon for night doses', () {
      expect(NotificationService.reminderTitle(morning), '☀️ Morning dose');
      expect(NotificationService.reminderTitle(night), '🌙 Night dose');
      expect(morning.isNight, isFalse);
      expect(night.isNight, isTrue);
    });

    test('spells out the dosage', () {
      expect(NotificationService.reminderBody(morning), 'Time for 500mg');
      expect(NotificationService.reminderBody(night),
          'Time for 500mg + 250mg (750mg)');
      final empty = morning.copyWith(tablets: []);
      expect(NotificationService.reminderBody(empty),
          'Time to take your medication');
    });
  });

  test('notification ids are stable per dose', () {
    // The native widget derives the same ids (ClarkoStore.kt) to clear a
    // reminder when its dose is ticked off there — keep these values in sync.
    expect(NotificationService.notificationId('morning'), 52004);
    expect(NotificationService.notificationId('night'), 17688);
    expect(NotificationService.notificationId('dose_1718000000000'), 96737);
  });
}
