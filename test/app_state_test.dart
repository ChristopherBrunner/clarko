import 'dart:convert';

import 'package:clarko/models/day.dart';
import 'package:clarko/models/dose.dart';
import 'package:clarko/models/medication_log.dart';
import 'package:clarko/services/storage.dart';
import 'package:clarko/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the shared_preferences-backed [Storage]. Like the
/// real one it hands out copies and takes a moment to answer, so operations
/// can interleave the way they do on a device.
class FakeStorage implements Storage {
  MedicationLog _stored = MedicationLog.empty();
  List<Dose> schedule = Dose.defaults();
  int saves = 0;

  static MedicationLog _copy(MedicationLog log) => MedicationLog.fromJson(
      jsonDecode(jsonEncode(log.toJson())) as Map<String, dynamic>);

  static Future<void> _latency() =>
      Future<void>.delayed(const Duration(milliseconds: 3));

  /// What is "on disk" right now.
  bool storedTaken(String doseId) =>
      _stored.isTaken(doseId, clarkoDay(DateTime.now()));

  /// Marks every dose taken on the day [daysAgo] days before today.
  void completeDay(int daysAgo) {
    final today = clarkoDay(DateTime.now());
    final day = DateTime(today.year, today.month, today.day - daysAgo);
    for (final dose in schedule) {
      _stored.setTaken(dose.id, day, true);
    }
  }

  /// A write made by someone other than the app: the home widget or the
  /// reminder's "Mark as taken" action.
  void writeFromOutside(String doseId, bool taken) =>
      _stored.setTaken(doseId, clarkoDay(DateTime.now()), taken);

  @override
  Future<MedicationLog> loadLog() async {
    await _latency();
    return _copy(_stored);
  }

  @override
  Future<void> saveLog(MedicationLog log) async {
    final snapshot = _copy(log);
    await _latency();
    _stored = snapshot;
    saves++;
  }

  @override
  Future<List<Dose>> loadSchedule() async => schedule;

  @override
  Future<void> saveSchedule(List<Dose> doses) async => schedule = doses;

  @override
  Future<int> loadThemeIndex() async => 0;

  @override
  Future<void> saveThemeIndex(int index) async {}
}

void main() {
  late FakeStorage storage;
  late AppState state;
  late Dose morning;
  late Dose night;

  setUp(() async {
    storage = FakeStorage();
    state = AppState(storage);
    await state.load();
    morning = state.doses.firstWhere((d) => d.id == 'morning');
    night = state.doses.firstWhere((d) => d.id == 'night');
  });

  tearDown(() => state.dispose());

  test('a tick made outside the app survives a later tick inside it',
      () async {
    // E.g. "Mark as taken" pressed on the reminder banner while the app is
    // open: the app has not reloaded, so its in-memory log is stale.
    storage.writeFromOutside('morning', true);
    expect(state.isTaken(morning), isFalse, reason: 'app view is stale');

    await state.setTaken(night, true);

    expect(storage.storedTaken('morning'), isTrue,
        reason: 'the outside tick must not be overwritten');
    expect(storage.storedTaken('night'), isTrue);
    // ...and the app has caught up with it.
    expect(state.isTaken(morning), isTrue);
    expect(state.isTaken(night), isTrue);
  });

  test('an untick made outside the app is not resurrected', () async {
    await state.setTaken(morning, true);
    storage.writeFromOutside('morning', false); // unticked on the widget

    await state.setTaken(night, true);

    expect(storage.storedTaken('morning'), isFalse);
    expect(state.isTaken(morning), isFalse);
    expect(storage.storedTaken('night'), isTrue);
  });

  test('taps in quick succession are all saved', () async {
    final first = state.setTaken(morning, true);
    final second = state.setTaken(night, true);
    // Both show immediately, before anything has been written.
    expect(state.isTaken(morning), isTrue);
    expect(state.isTaken(night), isTrue);

    await Future.wait([first, second]);

    expect(storage.storedTaken('morning'), isTrue);
    expect(storage.storedTaken('night'), isTrue);
    expect(state.isTaken(morning), isTrue);
    expect(state.isTaken(night), isTrue);
  });

  test('tick then untick in quick succession ends unticked', () async {
    await Future.wait([
      state.setTaken(morning, true),
      state.setTaken(morning, false),
    ]);

    expect(storage.storedTaken('morning'), isFalse);
    expect(state.isTaken(morning), isFalse);
  });

  test('a reload while a tap is being saved does not drop the tap', () async {
    final tap = state.setTaken(morning, true);
    final reload = state.reloadLog(); // e.g. the app resuming
    expect(state.isTaken(morning), isTrue);

    await Future.wait([tap, reload]);

    expect(state.isTaken(morning), isTrue);
    expect(storage.storedTaken('morning'), isTrue);
  });

  test('reload picks up changes made outside the app', () async {
    storage.writeFromOutside('night', true);
    await state.reloadLog();
    expect(state.isTaken(night), isTrue);
    expect(state.takenTodayCount, 1);
  });

  test('the tick that completes a milestone day reports it', () async {
    storage
      ..completeDay(1)
      ..completeDay(2);
    await state.reloadLog();
    expect(state.streak, 2);

    expect(await state.setTaken(morning, true), isNull,
        reason: 'day not complete yet');
    expect(await state.setTaken(night, true), 3);
    expect(state.streak, 3);
    // Unticking and ticking something else never reports a milestone.
    expect(await state.setTaken(night, false), isNull);
  });

  test('toggle flips what is shown and reports taken doses', () async {
    final taken = <String>[];
    state.onDoseTaken = (dose) async => taken.add(dose.id);

    await state.toggleTaken(morning);
    expect(state.isTaken(morning), isTrue);
    await state.toggleTaken(morning);
    expect(state.isTaken(morning), isFalse);

    expect(taken, ['morning'], reason: 'only reported when ticked');
    expect(storage.storedTaken('morning'), isFalse);
  });
}
