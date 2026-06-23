import 'package:home_widget/home_widget.dart';

import '../models/dose.dart';
import 'storage.dart';

/// Bridges app state to the Android home-screen widget.
///
/// The widget shows up to the first two enabled doses (typically Morning and
/// Night). Display values are pushed via [HomeWidget.saveWidgetData]; the
/// native provider reads them back out.
class WidgetService {
  // All widget size variants must be refreshed, otherwise a placed 3x1/2x1
  // widget keeps showing stale state after in-app changes.
  static const _androidNames = [
    'ClarkoWidgetProvider',
    'ClarkoWidgetWideProvider',
    'ClarkoWidgetSmallProvider',
  ];
  static const _maxDoses = 2;

  static Future<void> render(
    List<Dose> enabledDoses,
    bool Function(Dose) isTaken,
    int streak,
  ) async {
    final doses = enabledDoses.take(_maxDoses).toList();
    await HomeWidget.saveWidgetData<int>('streak', streak);

    for (var i = 0; i < _maxDoses; i++) {
      if (i < doses.length) {
        final dose = doses[i];
        await HomeWidget.saveWidgetData<bool>('dose${i}_present', true);
        await HomeWidget.saveWidgetData<String>('dose${i}_id', dose.id);
        await HomeWidget.saveWidgetData<String>('dose${i}_label', dose.label);
        await HomeWidget.saveWidgetData<String>(
            'dose${i}_time', _formatTime(dose.hour, dose.minute));
        await HomeWidget.saveWidgetData<bool>(
            'dose${i}_taken', isTaken(dose));
        // Day/night flag drives the sun/moon icon (esp. in compact views).
        await HomeWidget.saveWidgetData<bool>(
            'dose${i}_night', dose.hour >= 18 || dose.hour < 5);
      } else {
        await HomeWidget.saveWidgetData<bool>('dose${i}_present', false);
      }
    }

    for (final name in _androidNames) {
      await HomeWidget.updateWidget(androidName: name);
    }
  }

  static String _formatTime(int hour, int minute) {
    final period = hour < 12 ? 'AM' : 'PM';
    var h = hour % 12;
    if (h == 0) h = 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }
}

/// Handles taps on the widget's "taken" toggle. Runs in a background isolate
/// (registered via [HomeWidget.registerInteractivityCallback]), so it updates
/// storage directly and re-renders the widget.
@pragma('vm:entry-point')
Future<void> widgetInteractionCallback(Uri? uri) async {
  if (uri == null || uri.host != 'toggle') return;
  final id = uri.queryParameters['id'];
  if (id == null) return;

  final storage = Storage();
  final doses = await storage.loadSchedule();
  final log = await storage.loadLog();
  final now = DateTime.now();

  log.setTaken(id, now, !log.isTaken(id, now));
  await storage.saveLog(log);

  final enabled = doses.where((d) => d.enabled).toList();
  await WidgetService.render(
    enabled,
    (d) => log.isTaken(d.id, now),
    log.currentStreak(doses, now),
  );
}
