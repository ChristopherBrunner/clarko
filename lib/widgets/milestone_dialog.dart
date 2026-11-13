import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/streak_stage.dart';

/// Celebrates reaching a streak milestone: the card bounces in, the stage's
/// emoji bursts outwards, and the cat does its thing. Tap anywhere to close.
Future<void> showStreakMilestone(BuildContext context, int days) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withOpacity(0.6),
    transitionDuration: const Duration(milliseconds: 550),
    pageBuilder: (context, _, __) => _Celebration(days: days),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: animation,
          curve: Curves.elasticOut,
          reverseCurve: Curves.easeIn,
        ),
        child: child,
      ),
    ),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.days});

  final int days;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  static const _particles = 14;

  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = StreakStage.of(widget.days) ?? StreakStage.stages.first;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Emoji flying out from behind the card.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _burst,
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(_burst.value);
                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < _particles; i++)
                        Transform.translate(
                          offset: Offset.fromDirection(
                            i * 2 * math.pi / _particles + 0.3,
                            t * (170 + (i.isEven ? 40 : 0)),
                          ),
                          child: Transform.rotate(
                            angle: t * (i.isEven ? 1.2 : -1.2),
                            child: Opacity(
                              opacity: (1 - _burst.value * _burst.value)
                                  .clamp(0.0, 1.0),
                              child: Text(
                                stage.emoji,
                                style: TextStyle(
                                  fontSize: i.isEven ? 30 : 22,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Material(
              color: theme.colorScheme.surface,
              elevation: 12,
              borderRadius: BorderRadius.circular(26),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/wawa-cat-wawa.gif',
                      height: 200,
                      width: 280,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Column(
                        children: [
                          Text(
                            '${stage.emoji} ${widget.days} day streak!',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stage.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tap to continue',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
