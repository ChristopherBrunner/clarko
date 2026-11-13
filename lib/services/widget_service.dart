import 'package:home_widget/home_widget.dart';

/// Bridges the app to the Android home-screen widget.
///
/// The widget renders itself natively straight from the persisted schedule and
/// log (the same data [Storage] writes), always for the current calendar day —
/// so there is no separate copy of "what's taken" to keep in sync. All the app
/// has to do is ask it to redraw after something changed.
class WidgetService {
  // Any one provider is enough: a refresh redraws every size variant.
  static const _androidProvider = 'ClarkoWidgetProvider';

  /// Redraws all home-screen widgets from the persisted state. Call this only
  /// after the change has been saved. Pass [dark] to also update the theme the
  /// widget follows; leave it out to keep the one the app last set.
  static Future<void> refresh({bool? dark}) async {
    if (dark != null) {
      await HomeWidget.saveWidgetData<bool>('dark', dark);
    }
    await HomeWidget.updateWidget(androidName: _androidProvider);
  }
}
