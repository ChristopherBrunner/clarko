import 'package:flutter/material.dart';

import '../models/dose.dart';
import '../state/app_state.dart';
import '../widgets/dose_editor.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final doses = state.doses;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Clarko',
              style: TextStyle(
                fontFamily: 'Clarko',
                fontSize: 28,
                color: theme.colorScheme.primary,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(state.isDark(context)
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded),
                tooltip: state.isDark(context) ? 'Light mode' : 'Dark mode',
                onPressed: () => state.toggleTheme(context),
              ),
              IconButton(
                icon: const Icon(Icons.favorite_rounded),
                tooltip: 'A little something',
                onPressed: () => _showEasterEgg(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addDose(context),
            icon: const Icon(Icons.add),
            label: const Text('Add dose'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _StreakCard(
                streak: state.streak,
                takenToday: state.takenTodayCount,
                totalToday: state.enabledDoses.length,
              ),
              const SizedBox(height: 16),
              Text(
                "Today's doses",
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Tap to take · hold to edit',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (doses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No doses yet. Tap "Add dose" to get started.'),
                )
              else
                ...doses.map((dose) => _DoseCard(
                      dose: dose,
                      taken: state.isTaken(dose),
                      onToggle: () => state.toggleTaken(dose),
                      onEdit: () => _editDose(context, dose.id),
                    )),
            ],
          ),
        );
      },
    );
  }

  /// Opens an editor on a draft dose; it's only added to the schedule if the
  /// user taps "Add" (dismissing discards it).
  void _addDose(BuildContext context) {
    var draft = Dose(
      id: 'dose_${DateTime.now().millisecondsSinceEpoch}',
      label: 'New dose',
      hour: 12,
      minute: 0,
      tablets: [500],
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add dose',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DoseEditor(
                      dose: draft,
                      embedded: true,
                      onChanged: (updated) => setSheet(() => draft = updated),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            state.addDose(draft);
                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Opens a bottom sheet to edit the dose with [doseId] in place.
  void _editDose(BuildContext context, String doseId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            Dose? match;
            for (final d in state.doses) {
              if (d.id == doseId) match = d;
            }
            // Dose was deleted from within the sheet — close it.
            if (match == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(sheetContext).canPop()) {
                  Navigator.of(sheetContext).pop();
                }
              });
              return const SizedBox.shrink();
            }
            final dose = match;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit dose',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DoseEditor(
                      dose: dose,
                      embedded: true,
                      onChanged: state.updateDose,
                      onRemove: state.doses.length > 1
                          ? () {
                              state.removeDose(dose);
                              Navigator.of(sheetContext).pop();
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEasterEgg(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Image.asset(
            'assets/minion.gif',
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streak,
    required this.takenToday,
    required this.totalToday,
  });

  final int streak;
  final int takenToday;
  final int totalToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = streak > 0;
    final dayWord = streak == 1 ? 'day' : 'days';

    // Warm "on fire" palette only once a streak is actually reached;
    // otherwise stay neutral so it doesn't look achieved when it isn't.
    final Color background = active
        ? (isDark ? const Color(0xFF4A2E12) : const Color(0xFFFFE6C2))
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = active
        ? (isDark ? const Color(0xFFFFD8A8) : const Color(0xFF7A4A12))
        : theme.colorScheme.onSurfaceVariant;
    final Color iconColor =
        active ? const Color(0xFFFF7043) : theme.disabledColor;

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
              size: 44,
              color: iconColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? '$streak $dayWord in a row' : 'No streak yet',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalToday == 0
                        ? 'Nothing scheduled today'
                        : '$takenToday of $totalToday taken today',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.dose,
    required this.taken,
    required this.onToggle,
    required this.onEdit,
  });

  final Dose dose;
  final bool taken;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = dose.enabled;
    final highlight = taken && enabled;
    final night = dose.hour >= 18 || dose.hour < 5;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Card(
        elevation: 1,
        color:
            highlight ? theme.colorScheme.primaryContainer : theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: highlight
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: highlight ? 2 : 1,
          ),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Enabled doses toggle on tap; disabled ones jump straight to edit.
          onTap: enabled ? onToggle : onEdit,
          onLongPress: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  night ? Icons.dark_mode : Icons.wb_sunny,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dose.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? '${dose.time.format(context)}  ·  ${dose.dosageLabel}'
                            : 'Paused  ·  ${dose.dosageLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  !enabled
                      ? Icons.pause_circle_outline
                      : (taken
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked),
                  size: 32,
                  color: taken && enabled
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
