import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dose.dart';
import '../models/medication_log.dart';

/// Thin persistence layer over [SharedPreferences].
///
/// Everything is stored as JSON under a couple of keys. The Android home widget
/// reads (and, for its check buttons, writes) this same store natively — see
/// `ClarkoStore.kt` — so the keys and JSON shapes must stay in sync with it.
class Storage {
  static const _scheduleKey = 'schedule';
  static const _logKey = 'log';
  static const _themeKey = 'themeMode';

  Future<List<Dose>> loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_scheduleKey);
    if (raw == null) {
      // First run: persist the defaults, so the home widget (which reads the
      // stored schedule directly) shows the same doses as the app.
      final defaults = Dose.defaults();
      await saveSchedule(defaults);
      return defaults;
    }
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Dose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSchedule(List<Dose> doses) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(doses.map((d) => d.toJson()).toList());
    await prefs.setString(_scheduleKey, raw);
  }

  Future<MedicationLog> loadLog() async {
    final prefs = await SharedPreferences.getInstance();
    // Force a fresh read: the home widget (natively) and the notification
    // action's background isolate write the log too, and this isolate's
    // in-memory cache would otherwise be stale (showing pre-tap state and
    // clobbering it on the next save).
    await prefs.reload();
    final raw = prefs.getString(_logKey);
    if (raw == null) return MedicationLog.empty();
    return MedicationLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveLog(MedicationLog log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logKey, jsonEncode(log.toJson()));
  }

  /// Theme preference as a [ThemeMode] index (0 = system, 1 = light, 2 = dark).
  Future<int> loadThemeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_themeKey) ?? 0;
  }

  Future<void> saveThemeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, index);
  }
}
