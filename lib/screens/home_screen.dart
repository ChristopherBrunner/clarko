import 'package:flutter/material.dart';

import '../models/dose.dart';
import '../state/app_state.dart';
import '../widgets/dose_card.dart';
import '../widgets/dose_editor.dart';
import '../widgets/milestone_dialog.dart';
import '../widgets/streak_card.dart';
import 'streak_guide_screen.dart';

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
              // Hold the streak card for the guide to its stages.
              GestureDetector(
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StreakGuideScreen(),
                  ),
                ),
                child: StreakCard(
                  streak: state.streakInfo,
                  takenToday: state.takenTodayCount,
                  totalToday: state.enabledDoses.length,
                ),
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
                ...doses.map((dose) => DoseCard(
                      key: ValueKey(dose.id),
                      dose: dose,
                      taken: state.isTaken(dose),
                      onToggle: () => _toggle(context, dose),
                      onEdit: () => _editDose(context, dose.id),
                    )),
            ],
          ),
        );
      },
    );
  }

  /// Ticks / unticks [dose] and celebrates if that reached a streak milestone.
  Future<void> _toggle(BuildContext context, Dose dose) async {
    final milestone = await state.toggleTaken(dose);
    if (milestone != null && context.mounted) {
      await showStreakMilestone(context, milestone);
    }
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
