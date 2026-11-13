import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dose.dart';

/// One dose on the home screen: tap to tick it off, hold to edit.
///
/// Holding shows a fill spreading out from the finger; when it has covered
/// the card the editor opens. Letting go earlier is just a tap.
class DoseCard extends StatefulWidget {
  const DoseCard({
    super.key,
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
  State<DoseCard> createState() => _DoseCardState();
}

class _DoseCardState extends State<DoseCard>
    with SingleTickerProviderStateMixin {
  /// How long the card has to be held before the editor opens.
  static const _holdTime = Duration(milliseconds: 550);

  late final AnimationController _hold =
      AnimationController(vsync: this, duration: _holdTime)
        ..addStatusListener(_onHoldStatus);

  /// Share of the hold after which letting go no longer counts as a tap
  /// (about a third of a second in).
  static const _abandonAfter = 0.5;

  Offset _origin = Offset.zero;

  /// The current press already opened the editor, so its release is no tap.
  bool _opened = false;

  void _onHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _opened = true;
    HapticFeedback.mediumImpact();
    widget.onEdit();
    _release();
  }

  void _release() =>
      _hold.animateBack(0, duration: const Duration(milliseconds: 180));

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dose = widget.dose;
    final enabled = dose.enabled;
    final highlight = widget.taken && enabled;

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
        child: Semantics(
          button: true,
          onLongPress: widget.onEdit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              _opened = false;
              _origin = details.localPosition;
              _hold.forward(from: 0);
            },
            onTapUp: (_) {
              if (_opened) return;
              // Let go once the fill is well underway: an abandoned hold,
              // not a tap — do nothing rather than tick by accident.
              final abandoned = _hold.value > _abandonAfter;
              _release();
              if (abandoned) return;
              // Enabled doses toggle on tap; paused ones go straight to edit.
              enabled ? widget.onToggle() : widget.onEdit();
            },
            onTapCancel: () {
              if (!_opened) _release();
            },
            child: CustomPaint(
              painter: _HoldFillPainter(
                progress: _hold,
                origin: () => _origin,
                color: theme.colorScheme.primary,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      dose.isNight ? Icons.dark_mode : Icons.wb_sunny,
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
                          : (widget.taken
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked),
                      size: 32,
                      color: highlight
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A translucent disc growing from the touch point until it covers the card.
class _HoldFillPainter extends CustomPainter {
  _HoldFillPainter({
    required this.progress,
    required this.origin,
    required this.color,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Offset Function() origin;
  final Color color;

  /// Share of the hold that passes before anything shows, so a quick tap
  /// doesn't flash.
  static const _quiet = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final t = ((progress.value - _quiet) / (1 - _quiet)).clamp(0.0, 1.0);
    if (t == 0) return;
    final center = origin();
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - center).distance).reduce(math.max);
    final radius = reach * Curves.easeOut.transform(t);

    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(center, radius, Paint()..color = color.withOpacity(0.20));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withOpacity(0.55 * (1 - t) + 0.15),
    );
  }

  @override
  bool shouldRepaint(_HoldFillPainter old) =>
      old.color != color || old.progress != progress;
}
