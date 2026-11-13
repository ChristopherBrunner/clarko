import 'package:flutter/material.dart';

import '../models/medication_log.dart';
import '../models/streak_stage.dart';
import '../widgets/milestone_dialog.dart';
import '../widgets/streak_card.dart';

/// Shows every look the streak can take — each stage, the milestone
/// celebration, and how the streak safe is used and comes back — using the
/// real components. Opened by holding the streak card on the home screen.
class StreakGuideScreen extends StatelessWidget {
  const StreakGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 2),
          child: Text(
            text,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        );

    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );

    Widget example(String caption, Streak streak, {int taken = 2}) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(caption, style: theme.textTheme.labelLarge),
                  ),
                  if (streak.days > 0)
                    TextButton.icon(
                      onPressed: () =>
                          showStreakMilestone(context, streak.days),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Celebrate'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              StreakCard(streak: streak, takenToday: taken, totalToday: 2),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Streak guide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          heading('Stages'),
          note('The card grows with the streak. A day counts once every '
              'dose is ticked.'),
          example('No streak', const Streak(0), taken: 0),
          for (final stage in StreakStage.stages)
            example(
              'From ${stage.minDays} ${stage.minDays == 1 ? 'day' : 'days'}'
              ' · ${stage.title}',
              Streak(stage.minDays),
            ),
          heading('Milestones'),
          note('Reaching one of these in the app plays the celebration. '
              'Tap one to see it.'),
          Wrap(
            spacing: 8,
            children: [
              for (final days in StreakStage.milestones)
                ActionChip(
                  label: Text('$days'),
                  onPressed: () => showStreakMilestone(context, days),
                ),
            ],
          ),
          heading('Streak safe'),
          note('One missed day is forgiven: it is not counted, but the '
              'streak carries on. Tap the shield on a card for details.'),
          example('Ready', const Streak(12)),
          example(
            'You missed yesterday: streak kept, safe used',
            const Streak(12, safeUsed: true, daysSinceSafe: 0),
            taken: 0,
          ),
          example(
            'Four full days later: still recharging',
            const Streak(16, safeUsed: true, daysSinceSafe: 4),
          ),
          example(
            'After ${Streak.rechargeDays} full days: ready again',
            const Streak(18, safeUsed: true, daysSinceSafe: Streak.rechargeDays),
          ),
          example(
            'Two missed days in a row: the streak starts over',
            const Streak(0),
            taken: 0,
          ),
        ],
      ),
    );
  }
}
