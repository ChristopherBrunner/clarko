/// The look of a streak, which grows with its length: a sprout becomes a
/// flame, a rocket, a star, a diamond and finally a crown.
///
/// The widget shows the same emoji (`ClarkoStore.streakEmoji` in Kotlin) —
/// keep the thresholds in sync.
class StreakStage {
  const StreakStage(this.minDays, this.emoji, this.title);

  /// First streak length (in days) that reaches this stage.
  final int minDays;
  final String emoji;
  final String title;

  static const stages = [
    StreakStage(1, '🌱', 'Sprouting'),
    StreakStage(3, '🔥', 'On fire'),
    StreakStage(7, '🚀', 'Taking off'),
    StreakStage(30, '🌟', 'Shining'),
    StreakStage(60, '⚡', 'Electric'),
    StreakStage(100, '💎', 'Diamond'),
    StreakStage(150, '🏆', 'Champion'),
    StreakStage(250, '🐉', 'Dragon'),
    StreakStage(365, '👑', 'Legendary'),
    StreakStage(500, '🦄', 'Mythic'),
    StreakStage(730, '🌌', 'Cosmic'),
    StreakStage(900, '🐐', 'The GOAT'),
    StreakStage(1000, '🐱', 'The Wawa'),
  ];

  /// Streak lengths worth a little celebration.
  static const milestones = [
    3, 7, 14, 30, 60, 100, 150, 200, 250, 300, 365, 500, 730, 900, 1000, //
  ];

  /// Index into [stages] for a streak of [days], or -1 without a streak.
  static int indexOf(int days) {
    var index = -1;
    for (var i = 0; i < stages.length; i++) {
      if (days >= stages[i].minDays) index = i;
    }
    return index;
  }

  /// The stage of a streak of [days]; null without a streak.
  static StreakStage? of(int days) {
    final index = indexOf(days);
    return index < 0 ? null : stages[index];
  }

  /// The highest milestone passed when a streak grows from [before] to
  /// [after] days, or null if none was.
  static int? milestoneReached(int before, int after) {
    int? reached;
    for (final milestone in milestones) {
      if (before < milestone && milestone <= after) reached = milestone;
    }
    return reached;
  }
}
