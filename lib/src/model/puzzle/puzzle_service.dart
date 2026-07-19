import 'dart:math' show max;

import 'package:async/async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_batch_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:logging/logging.dart';
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
      _ref,
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
  PuzzleService(
    this._ref, {
    required this.batchStorage,
    required this.puzzleStorage,
    required this.queueLength,
  });

  final Ref _ref;
  final int queueLength;
  final PuzzleBatchStorage batchStorage;
  final PuzzleStorage puzzleStorage;
  final Logger _log = Logger('PuzzleService');

  /// Loads the next puzzle from database and the glicko rating if available.
  ///
  /// Will sync with server if necessary.
  /// This future should never fail on network errors.
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

  /// Update puzzle queue with the solved puzzle and returns the next puzzle.
  ///
  /// This future should never fail.
  Future<PuzzleContext?> solve({
    required UserId? userId,
    required PuzzleSolution solution,
    required Puzzle puzzle,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    puzzleStorage.save(puzzle: puzzle);
    final batch = await batchStorage.fetch(userId: userId, angle: angle);
    if (batch != null) {
      await batchStorage.save(
        userId: userId,
        angle: angle,
        data: PuzzleBatch(
          solved: IList([...batch.solved, solution]),
          unsolved: batch.unsolved.where((p) => p.puzzle.id != puzzle.puzzle.id).toIList(),
        ),
      );
    }
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

  /// Synchronize the puzzle queue with the bundled offline puzzle database.
  ///
  /// This task will load missing puzzles so the queue length is always equal to
  /// `queueLength`.
  ///
  /// This method should never fail.
  FutureResult<(PuzzleBatch?, PuzzleGlicko?, IList<PuzzleRound>?)> _syncAndLoadData(
    UserId? userId,
    PuzzleAngle angle,
  ) async {
    final data = await batchStorage.fetch(userId: userId, angle: angle);

    final unsolved = data?.unsolved ?? IList(const []);
    final solved = data?.solved ?? IList(const []);
    final deficit = max(0, queueLength - unsolved.length);

    if (deficit == 0 && solved.isEmpty) {
      return Result.value((data, null, null));
    }

    _log.fine('Will load offline puzzles (deficit: $deficit, solved: ${solved.length})');

    try {
      final offlineRepository = await _ref.read(offlinePuzzleRepositoryProvider.future);
      final puzzles = deficit > 0
          ? await offlineRepository.randomPuzzles(limit: deficit, angle: angle)
          : IList<Puzzle>(const []);
      final newBatch = PuzzleBatch(
        solved: IList(const []),
        unsolved: IList([...unsolved, ...puzzles]),
      );
      await batchStorage.save(userId: userId, angle: angle, data: newBatch);
      return Result.value((newBatch, null, null));
    } catch (e, stackTrace) {
      _log.warning('Could not load offline puzzles', e, stackTrace);
      return Result.value((data, null, null));
    }
  }
}
