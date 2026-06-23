# clarko 💊

A super-simple, local medication tracker — built for a twice-daily Levetiracetam
schedule but works for any meds. Android-first (Flutter, so iOS stays possible later).

## Features

- **Today's doses** — Morning and Night doses with a tap-to-take checklist.
- **Editable schedule** — change reminder times, add/remove doses, and configure
  the tablet breakdown & dosage (defaults to 500mg + 250mg = 750mg Levetiracetam).
- **Reminders** — a daily local notification per dose, with a "Mark as taken"
  action button right on the notification.
- **Home-screen widget** — shows today's doses + your streak; tap a dose to mark
  it taken without opening the app.
- **Adherence streak** — consecutive days where every enabled dose was taken
  (today counts as in-progress, so an unfinished today never breaks the streak).
- **Local + persistent** — all data is stored on-device via `shared_preferences`.
  (Cross-install/cloud sync is intentionally deferred — see below.)

## Project layout

| Path | Purpose |
| --- | --- |
| `lib/models/` | `Dose` (schedule + tablets) and `MedicationLog` (taken log, streak) |
| `lib/services/storage.dart` | JSON persistence over `shared_preferences` |
| `lib/services/notification_service.dart` | Scheduled reminders + background "Mark as taken" |
| `lib/services/widget_service.dart` | Pushes data to the Android widget + handles widget taps |
| `lib/state/app_state.dart` | Central `ChangeNotifier` tying it together |
| `lib/screens/` | Home and Settings screens |
| `android/app/src/main/kotlin/.../ClarkoWidgetProvider.kt` | Native home-widget provider |

The app's `shared_preferences` is the single source of truth. Notifications and the
home widget run in background isolates and write back to it directly; the app
reloads the log on resume to reflect any out-of-app changes.

## Toolchain notes (important)

This project is pinned to an older Flutter (3.22 / Dart 3.4). The Android build
needs a specific, compatible set of versions — don't bump these casually:

- **Gradle 7.6.3** caps the Android Gradle Plugin at 7.4.x.
- **AGP 7.4.2** — required by `desugar_jdk_libs` 2.0.4 (which `flutter_local_notifications` needs).
- **Kotlin 1.8.22** + `kotlin-stdlib` forced to 1.8.22 (`app/build.gradle`) — newer
  stdlib can't be dexed by AGP 7.4.2's D8.
- **`home_widget` 0.6.0** — newer releases pull in Compose deps that require AGP 8+.

## Run / build

```sh
flutter pub get
flutter run                # debug on a connected Android device/emulator
flutter test               # unit tests (streak logic, serialization)
flutter build apk --debug  # verify the full native build
```

## Deferred / future

- Cross-install persistence (survive uninstall) — would need Android Auto Backup
  or cloud sync (e.g. Firebase). Left out of v1 by choice.
- iOS widget (WidgetKit) if/when iOS is targeted.
