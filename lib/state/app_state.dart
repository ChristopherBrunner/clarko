import 'dart:async';

import 'package:flutter/material.dart';

import '../models/day.dart';
import '../models/dose.dart';
import '../models/medication_log.dart';
import '../models/streak_stage.dart';
import '../services/storage.dart';

/// Central app state: the dose schedule and the taken-log, persisted via
/// [Storage]. UI listens to this and rebuilds on change.
class AppState extends ChangeNotifier {
  AppState(this._storage);

  final Storage _storage;

  List<Dose> _doses = [];
  MedicationLog _log = MedicationLog.empty();
  ThemeMode _themeMode = ThemeMode.system;
  bool _loaded = false;
  Timer? _newDayTimer;

  ThemeMode get themeMode => _themeMode;
  bool isDark(BuildContext context) => _themeMode == ThemeMode.system
      ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
      : _themeMode == ThemeMode.dark;

  /// Resolved dark/light without a [BuildContext] (used for widget rendering).
  bool get effectiveDark => _themeMode == ThemeMode.system
      ? WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark
      : _themeMode == ThemeMode.dark;

  /// Invoked after the schedule changes so reminders can be re-synced.
  Future<void> Function(List<Dose> doses)? onScheduleChanged;

  /// Invoked after any state change so the home widget can be refreshed.
  Future<void> Function()? onStateChanged;

  /// Invoked when a dose is marked as taken in the app, so a reminder for it
  /// that is still showing can be cleared.
  Future<void> Function(Dose dose)? onDoseTaken;

  bool get loaded => _loaded;
  List<Dose> get doses => List.unmodifiable(_doses);
  List<Dose> get enabledDoses =>
      _doses.where((d) => d.enabled).toList(growable: false);

  Future<void> load() async {
    _doses = await _storage.loadSchedule();
    _log = await _storage.loadLog();
    _themeMode = ThemeMode.values[await _storage.loadThemeIndex()];
    _log.prune(_today);
    _loaded = true;
    _armNewDayTimer();
    notifyListeners();
    await onScheduleChanged?.call(_doses);
    await onStateChanged?.call();
  }

  /// The Clarko day it is right now (days run 03:00 to 03:00, see day.dart).
  DateTime get _today => clarkoDay(DateTime.now());

  /// "Today" is always derived from the clock, so when a new day starts while
  /// the app is open all it takes is a rebuild — this fires just after the
  /// day changes to trigger one (and re-arms itself for the following night).
  void _armNewDayTimer() {
    _newDayTimer?.cancel();
    final now = DateTime.now();
    _newDayTimer = Timer(
      nextDayStart(now).difference(now) + const Duration(seconds: 1),
      reloadLog,
    );
  }

  @override
  void dispose() {
    _newDayTimer?.cancel();
    super.dispose();
  }

  /// Flips between light and dark (the app-bar "light mode" toggle).
  Future<void> toggleTheme(BuildContext context) async {
    _themeMode = isDark(context) ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await _storage.saveThemeIndex(_themeMode.index);
    await onStateChanged?.call(); // re-render widget in the new theme
  }

  // The stored log has other writers besides this class: the home widget
  // (natively) and the reminder's "Mark as taken" (a background isolate). So
  // the in-memory [_log] is only ever a *view* of storage, never the thing
  // that gets saved — see [setTaken]. Everything that touches the stored log
  // runs through this queue, one at a time, so a reload can't slip in between
  // another operation's read and its write.
  Future<void> _logQueue = Future.value();

  /// In-app changes already shown on screen but not yet written to storage.
  int _unsavedChanges = 0;

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _logQueue.then((_) => action());
    _logQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Re-reads the log from storage and redraws for the current day. Called
  /// when the app comes back to the foreground, after a "Mark as taken" from a
  /// notification, and when a new day starts.
  Future<void> reloadLog() async {
    await _exclusive(() async {
      final stored = await _storage.loadLog();
      // A tap that is still on its way to storage must not vanish from the
      // screen; its own save adopts the stored state when it lands.
      if (_unsavedChanges == 0) _log = stored;
    });
    _armNewDayTimer();
    notifyListeners();
    await onStateChanged?.call();
  }

  bool isTaken(Dose dose, [DateTime? date]) =>
      _log.isTaken(dose.id, date ?? _today);

  /// Current streak including the state of the streak safe.
  Streak get streakInfo => _log.streak(_doses, _today);

  int get streak => streakInfo.days;

  int get takenTodayCount =>
      enabledDoses.where((d) => isTaken(d)).length;

  Future<int?> toggleTaken(Dose dose) =>
      setTaken(dose, !_log.isTaken(dose.id, _today));

  /// Marks [dose] taken / not taken today. Completes with the streak
  /// milestone this tick reached (see [StreakStage.milestones]), if any.
  Future<int?> setTaken(Dose dose, bool taken) async {
    final day = _today;
    final streakBefore = streakInfo.days;
    // Show the change straight away…
    _log.setTaken(dose.id, day, taken);
    final milestone = taken
        ? StreakStage.milestoneReached(streakBefore, streakInfo.days)
        : null;
    _unsavedChanges++;
    notifyListeners();

    // …but write it on top of what is actually stored, not from this
    // in-memory copy. If the widget or a reminder ticked something since we
    // last read the log, saving our copy would silently undo that tick.
    await _exclusive(() async {
      try {
        final stored = await _storage.loadLog();
        stored.setTaken(dose.id, day, taken);
        stored.prune(day);
        await _storage.saveLog(stored);
        // Adopt the stored state once every pending tap has been written
        // (earlier ones keep showing the optimistic copy until then).
        if (_unsavedChanges == 1) _log = stored;
      } finally {
        _unsavedChanges--;
      }
    });

    notifyListeners();
    await onStateChanged?.call();
    if (taken) await onDoseTaken?.call(dose);
    return milestone;
  }

  Future<void> saveSchedule(List<Dose> doses) async {
    _doses = doses;
    await _persistSchedule();
  }

  /// Replace a single dose in-place by id and persist.
  Future<void> updateDose(Dose updated) async {
    final index = _doses.indexWhere((d) => d.id == updated.id);
    if (index == -1) return;
    _doses[index] = updated;
    await _persistSchedule();
  }

  Future<void> addDose(Dose dose) async {
    _doses.add(dose);
    await _persistSchedule();
  }

  Future<void> removeDose(Dose dose) async {
    _doses.removeWhere((d) => d.id == dose.id);
    await _persistSchedule();
  }

  Future<void> _persistSchedule() async {
    notifyListeners();
    await _storage.saveSchedule(_doses);
    await onScheduleChanged?.call(_doses);
    await onStateChanged?.call();
  }
}
