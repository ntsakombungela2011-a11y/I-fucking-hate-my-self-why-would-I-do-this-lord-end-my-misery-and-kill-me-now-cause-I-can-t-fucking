import 'package:async/async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_batch_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:result_extensions/result_extensions.dart';

part 'puzzle_service.freezed.dart';

/// Size of puzzle local cache
const kPuzzleLocalQueueLength = 50;

/// A provider for [PuzzleService].
final puzzleServiceProvider = FutureProvider<PuzzleService>((Ref ref) {
  return ref.read(puzzleServiceFactoryProvider)(queueLength: kPuzzleLocalQueueLength);
}, name: 'PuzzleServiceProvider');

/// A provider for [PuzzleServiceFactory].
final puzzleServiceFactoryProvider = Provider<PuzzleServiceFactory>((Ref ref) {
  return PuzzleServiceFactory(ref);
}, name: 'PuzzleServiceFactoryProvider');

class PuzzleServiceFactory {
  PuzzleServiceFactory(this._ref);

  final Ref _ref;

  Future<PuzzleService> call({required int queueLength}) async {
    return PuzzleService(
      batchStorage: await _ref.read(puzzleBatchStorageProvider.future),
      puzzleStorage: await _ref.read(puzzleStorageProvider.future),
      queueLength: queueLength,
    );
  }
}

@freezed
sealed class PuzzleContext with _$PuzzleContext {
  const factory PuzzleContext({
    required Puzzle puzzle,
    required PuzzleAngle angle,
    required UserId? userId,

    /// Current Glicko rating of the user if available.
    PuzzleGlicko? glicko,

    /// List of solved puzzle results if available.
    IList<PuzzleRound>? rounds,

    /// If true, the result won't be recorded on the server for this puzzle.
    bool? casual,
    bool? isPuzzleStreak,

    /// Remaining puzzle IDs to replay after the current one.
    IList<PuzzleId>? replayRemaining,
  }) = _PuzzleContext;
}

class PuzzleService {
  PuzzleService({
    required this.batchStorage,
    required this.puzzleStorage,
    required this.queueLength,
  });

  final int queueLength;
  final PuzzleBatchStorage batchStorage;
  final PuzzleStorage puzzleStorage;

  /// Loads the next puzzle from the offline local queue if available.
  ///
  /// This future returns `null` when the curated offline queue is empty.
  Future<PuzzleContext?> nextPuzzle({
    required UserId? userId,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    final result = await _syncAndLoadData(userId, angle);
    return result.fold(
      (data) {
        final (batch, glicko, rounds) = data;
        final puzzle = batch == null || batch.unsolved.isEmpty ? null : batch.unsolved.first;
        if (puzzle == null) return null;
        return PuzzleContext(
          puzzle: puzzle,
          angle: angle,
          userId: userId,
          glicko: glicko,
          rounds: rounds,
        );
      },
      (_, _) => null,
    );
  }

  /// Updates local puzzle history and returns the next offline puzzle if available.
  Future<PuzzleContext?> solve({
    required UserId? userId,
    required PuzzleSolution solution,
    required Puzzle puzzle,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    puzzleStorage.save(puzzle: puzzle);
    return nextPuzzle(userId: userId, angle: angle);
  }

  /// Clears the current puzzle batch, fetches a new one and returns the next puzzle.
  Future<PuzzleContext?> resetBatch({
    required UserId? userId,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    return nextPuzzle(userId: userId, angle: angle);
  }

  /// Deletes the puzzle batch of [angle] from the local storage.
  Future<void> deleteBatch({required UserId? userId, required PuzzleAngle angle}) async {
    await batchStorage.delete(userId: userId, angle: angle);
  }

  /// Loads the already-curated offline puzzle queue from local storage.
  ///
  /// Network puzzle refills were removed with the offline pivot. If no curated
  /// batch exists for [angle], callers receive an empty result and show an
  /// honest offline empty state.
  FutureResult<(PuzzleBatch?, PuzzleGlicko?, IList<PuzzleRound>?)> _syncAndLoadData(
    UserId? userId,
    PuzzleAngle angle,
  ) async {
    final data = await batchStorage.fetch(userId: userId, angle: angle);
    return Result.value((data, null, null));
  }
}
