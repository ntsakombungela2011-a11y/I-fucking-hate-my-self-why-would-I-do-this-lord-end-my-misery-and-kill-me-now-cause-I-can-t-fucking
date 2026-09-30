import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/service/sound_service.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_batch_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_service.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';

part 'puzzle_streak.freezed.dart';
part 'puzzle_streak.g.dart';

typedef Streak = IList<PuzzleId>;

@Freezed(fromJson: true, toJson: true)
sealed class PuzzleStreak with _$PuzzleStreak {
  const PuzzleStreak._();

  const factory PuzzleStreak({
    required Streak streak,
    required int index,
    required bool hasSkipped,
    required bool finished,
    required DateTime timestamp,
  }) = _PuzzleStreak;

  PuzzleId? get nextId => streak.getOrNull(index + 1);

  factory PuzzleStreak.fromJson(Map<String, dynamic> json) => _$PuzzleStreakFromJson(json);
}

/// [PuzzleStreak] with its current [Puzzle].
typedef StreakState = ({PuzzleStreak streak, Puzzle puzzle, Puzzle? nextPuzzle});

final puzzleStreakControllerProvider =
    AsyncNotifierProvider.autoDispose<PuzzleStreakController, StreakState>(
      PuzzleStreakController.new,
      name: 'PuzzleStreakControllerProvider',
    );

class PuzzleStreakController extends AsyncNotifier<StreakState> {
  @override
  Future<StreakState> build() async {
    final authUser = ref.read(authControllerProvider);
    final puzzle = await _loadPuzzleAt(0, userId: authUser?.user.id);
    final nextPuzzle = await _loadPuzzleAt(1, userId: authUser?.user.id);

    return (
      streak: PuzzleStreak(
        streak: IList([puzzle.puzzle.id, nextPuzzle.puzzle.id]),
        index: 0,
        hasSkipped: false,
        finished: false,
        timestamp: DateTime.now(),
      ),
      puzzle: puzzle,
      nextPuzzle: nextPuzzle,
    );
  }

  void skipMove() {
    if (!state.hasValue) return;

    state = AsyncData((
      streak: state.requireValue.streak.copyWith(hasSkipped: true),
      puzzle: state.requireValue.puzzle,
      nextPuzzle: state.requireValue.nextPuzzle,
    ));
  }

  /// Advance the streak to the next puzzle.
  Future<void> next() async {
    if (!state.hasValue || state.requireValue.nextPuzzle == null) {
      return;
    }
    ref.read(soundServiceProvider).play(Sound.confirmation);

    final authUser = ref.read(authControllerProvider);
    final currentStreak = state.requireValue.streak;
    final currentPuzzle = state.requireValue.nextPuzzle!;
    final nextPuzzle = await _loadPuzzleAt(currentStreak.index + 2, userId: authUser?.user.id);

    state = AsyncData((
      streak: currentStreak.copyWith(
        index: currentStreak.index + 1,
        streak: currentStreak.streak.add(nextPuzzle.puzzle.id),
      ),
      puzzle: currentPuzzle,
      nextPuzzle: nextPuzzle,
    ));
  }

  Future<Puzzle> _loadPuzzleAt(int index, {required UserId? userId}) async {
    final puzzleService = await ref.read(puzzleServiceFactoryProvider)(
      queueLength: kPuzzleLocalQueueLength,
    );

    // Align Puzzle Streak with the offline Puzzle Themes data path: populate/read
    // the local mix queue instead of calling the removed network streak endpoint.
    await puzzleService.nextPuzzle(
      userId: userId,
      angle: const PuzzleTheme(PuzzleThemeKey.mix),
    );
    final batch = await ref.read(puzzleBatchStorageProvider.future).then(
      (storage) => storage.fetch(userId: userId, angle: const PuzzleTheme(PuzzleThemeKey.mix)),
    );
    final puzzle = batch?.unsolved.getOrNull(index);
    if (puzzle == null) {
      throw const FormatException('No offline puzzles available for Puzzle Streak.');
    }
    return puzzle;
  }

  Future<void> gameOver() async {
    if (!state.hasValue) return;

    state = AsyncData((
      streak: state.requireValue.streak.copyWith(finished: true),
      puzzle: state.requireValue.puzzle,
      nextPuzzle: state.requireValue.nextPuzzle,
    ));
  }
}
