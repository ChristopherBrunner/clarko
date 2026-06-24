import 'package:flutter/material.dart';

import '../models/dose.dart';
import '../models/medication_log.dart';
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

  bool get loaded => _loaded;
  List<Dose> get doses => List.unmodifiable(_doses);
  List<Dose> get enabledDoses =>
      _doses.where((d) => d.enabled).toList(growable: false);

  Future<void> load() async {
    _doses = await _storage.loadSchedule();
    _log = await _storage.loadLog();
    _themeMode = ThemeMode.values[await _storage.loadThemeIndex()];
    _log.prune(DateTime.now());
    _loaded = true;
    notifyListeners();
    await onScheduleChanged?.call(_doses);
    await onStateChanged?.call();
  }

  /// Flips between light and dark (the app-bar "light mode" toggle).
  Future<void> toggleTheme(BuildContext context) async {
    _themeMode = isDark(context) ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await _storage.saveThemeIndex(_themeMode.index);
    await onStateChanged?.call(); // re-render widget in the new theme
  }

  /// Re-reads the log from storage (e.g. after a background "Mark as taken").
  Future<void> reloadLog() async {
    _log = await _storage.loadLog();
    notifyListeners();
    await onStateChanged?.call();
  }

  bool isTaken(Dose dose, [DateTime? date]) =>
      _log.isTaken(dose.id, date ?? DateTime.now());

  int get streak => _log.currentStreak(_doses, DateTime.now());

  int get takenTodayCount =>
      enabledDoses.where((d) => isTaken(d)).length;

  Future<void> toggleTaken(Dose dose) async {
    final now = DateTime.now();
    _log.setTaken(dose.id, now, !_log.isTaken(dose.id, now));
    await _persistLog();
  }

  Future<void> setTaken(Dose dose, bool taken) async {
    _log.setTaken(dose.id, DateTime.now(), taken);
    await _persistLog();
  }

  Future<void> _persistLog() async {
    notifyListeners();
    await _storage.saveLog(_log);
    await onStateChanged?.call();
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
