import 'package:flutter/material.dart';

import '../models/medication_log.dart';
import '../models/streak_stage.dart';

/// The streak header on the home screen. Its look grows with the streak (see
/// [StreakStage]); its size never changes, so ticking doses doesn't make the
/// page jump.
class StreakCard extends StatelessWidget {
  const StreakCard({
    super.key,
    required this.streak,
    required this.takenToday,
    required this.totalToday,
  });

  final Streak streak;
  final int takenToday;
  final int totalToday;

  // One palette per stage: [light top, light bottom, light text,
  //                         dark top, dark bottom, dark text].
  static const _palettes = [
    [0xFFE2F4E6, 0xFFCDEBD5, 0xFF1F5132, 0xFF1D3828, 0xFF173020, 0xFFBFE8CB],
    [0xFFFFE9C9, 0xFFFFD7A3, 0xFF7A4A12, 0xFF4A2E12, 0xFF5A3410, 0xFFFFD8A8],
    [0xFFFFDDCF, 0xFFFFC4B2, 0xFF7A2E1E, 0xFF55261C, 0xFF692B21, 0xFFFFD0C2],
    [0xFFFFF1BD, 0xFFFFE188, 0xFF6B5200, 0xFF4D3D0C, 0xFF61500F, 0xFFFFE9A6],
    [0xFFE0F7F4, 0xFFC2EFE8, 0xFF0B5A52, 0xFF0F3D38, 0xFF0E4C45, 0xFFBFF0E8],
    [0xFFD9F1FF, 0xFFBCE4FF, 0xFF0B4A6B, 0xFF10384F, 0xFF0E4663, 0xFFC5EAFF],
    [0xFFFFE4EC, 0xFFFFC9D9, 0xFF7A1F3D, 0xFF4F1B2C, 0xFF632036, 0xFFFFD0DE],
    [0xFFE0E4FF, 0xFFC5CCFF, 0xFF27307A, 0xFF222A5C, 0xFF2B3575, 0xFFD0D6FF],
    [0xFFECDFFF, 0xFFDAC4FF, 0xFF4A2A80, 0xFF3A235C, 0xFF4A2C77, 0xFFE6D4FF],
    [0xFFFFE0F5, 0xFFFFC4EA, 0xFF7A1F63, 0xFF4F1B43, 0xFF652155, 0xFFFFD0EE],
    [0xFFDDE3F5, 0xFFC0CAEC, 0xFF1B2A5C, 0xFF141B3D, 0xFF1C2654, 0xFFC9D4FF],
    [0xFFFFF3C4, 0xFFFFD98A, 0xFF6B4300, 0xFF4A3508, 0xFF6B4A0A, 0xFFFFE7A8],
    [0xFFFFE3D6, 0xFFFFC7E3, 0xFF6B2248, 0xFF52233A, 0xFF3B2A63, 0xFFFFD9EC],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final days = streak.days;
    final stageIndex = StreakStage.indexOf(days);
    final stage = stageIndex < 0 ? null : StreakStage.stages[stageIndex];

    // Neutral until a streak is actually reached, so it doesn't look
    // achieved when it isn't.
    final neutral = theme.colorScheme.surfaceContainerHighest;
    final palette = stage == null ? null : _palettes[stageIndex];
    final offset = isDark ? 3 : 0;
    final top = palette == null ? neutral : Color(palette[offset]);
    final bottom = palette == null ? neutral : Color(palette[offset + 1]);
    final foreground = palette == null
        ? theme.colorScheme.onSurfaceVariant
        : Color(palette[offset + 2]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: Row(
        children: [
          // Fixed box: bigger stages get a bigger emoji, not a bigger card.
          SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: Curves.elasticOut,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: stage == null
                    ? Icon(
                        Icons.local_fire_department_outlined,
                        key: const ValueKey('none'),
                        size: 40,
                        color: theme.disabledColor,
                      )
                    : Text(
                        stage.emoji,
                        // Re-pops whenever the count changes.
                        key: ValueKey(days),
                        style: TextStyle(fontSize: 32.0 + stageIndex * 1.75),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage == null
                      ? 'No streak yet'
                      : '$days ${days == 1 ? 'day' : 'days'} in a row',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  totalToday == 0
                      ? 'Nothing scheduled today'
                      : '$takenToday of $totalToday taken today'
                          '${stage == null ? '' : ' · ${stage.title}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
          if (stage != null) ...[
            const SizedBox(width: 8),
            _SafeBadge(streak: streak, isDark: isDark, muted: foreground),
          ],
        ],
      ),
    );
  }
}

/// Small shield showing the "streak safe": turquoise when a missed day would
/// be forgiven, muted with a countdown while it recharges. Tap for details.
class _SafeBadge extends StatelessWidget {
  const _SafeBadge({
    required this.streak,
    required this.isDark,
    required this.muted,
  });

  final Streak streak;
  final bool isDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final ready = streak.safeReady;
    final left = streak.rechargeIn;
    final turquoise =
        isDark ? const Color(0xFF4DD0E1) : const Color(0xFF00838F);
    final color = ready ? turquoise : muted.withOpacity(0.65);

    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      message: ready
          ? 'Streak safe ready: one missed day is forgiven.'
          : 'Streak safe used. Ready again after $left full '
              '${left == 1 ? 'day' : 'days'}.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(ready ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.shield_rounded : Icons.shield_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              ready ? 'Safe' : '${left}d',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
