import 'package:clarko/models/streak_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the stage grows with the streak', () {
    expect(StreakStage.of(0), isNull);
    expect(StreakStage.of(1)!.emoji, '🌱');
    expect(StreakStage.of(2)!.emoji, '🌱');
    expect(StreakStage.of(3)!.emoji, '🔥');
    expect(StreakStage.of(7)!.emoji, '🚀');
    expect(StreakStage.of(29)!.emoji, '🚀');
    expect(StreakStage.of(30)!.emoji, '🌟');
    expect(StreakStage.of(60)!.emoji, '⚡');
    expect(StreakStage.of(100)!.emoji, '💎');
    expect(StreakStage.of(150)!.emoji, '🏆');
    expect(StreakStage.of(250)!.emoji, '🐉');
    expect(StreakStage.of(365)!.emoji, '👑');
    expect(StreakStage.of(500)!.emoji, '🦄');
    expect(StreakStage.of(730)!.emoji, '🌌');
    expect(StreakStage.of(900)!.emoji, '🐐');
    expect(StreakStage.of(1000)!.emoji, '🐱');
    expect(StreakStage.of(2000)!.emoji, '🐱');
  });

  test('milestones are reported once, when they are passed', () {
    expect(StreakStage.milestoneReached(2, 3), 3);
    expect(StreakStage.milestoneReached(3, 4), isNull);
    expect(StreakStage.milestoneReached(6, 7), 7);
    expect(StreakStage.milestoneReached(99, 100), 100);
    expect(StreakStage.milestoneReached(7, 7), isNull);
    // A late tick can make the streak jump over several: the biggest wins.
    expect(StreakStage.milestoneReached(2, 8), 7);
    expect(StreakStage.milestoneReached(5, 4), isNull);
  });
}
