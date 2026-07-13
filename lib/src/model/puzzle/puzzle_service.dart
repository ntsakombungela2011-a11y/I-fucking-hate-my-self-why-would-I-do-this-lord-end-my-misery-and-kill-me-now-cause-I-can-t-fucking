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
      offlineRepository: await _ref.read(offlinePuzzleRepositoryProvider.future),
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
    required this.offlineRepository,
    required this.batchStorage,
    required this.puzzleStorage,
    required this.queueLength,
  });

  final int queueLength;
  final OfflinePuzzleRepository offlineRepository;
  final PuzzleBatchStorage batchStorage;
  final PuzzleStorage puzzleStorage;

  /// Loads the next puzzle from the bundled offline puzzle database.
  Future<PuzzleContext?> nextPuzzle({
    required UserId? userId,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    final batch = await _syncAndLoadData(userId, angle);
    final puzzle = batch == null || batch.unsolved.isEmpty ? null : batch.unsolved.first;
    if (puzzle == null) return null;
    return PuzzleContext(puzzle: puzzle, angle: angle, userId: userId);
  }

  /// Updates the offline puzzle queue with the solved puzzle and returns the next puzzle.
  Future<PuzzleContext?> solve({
    required UserId? userId,
    required PuzzleSolution solution,
    required Puzzle puzzle,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    puzzleStorage.save(puzzle: puzzle);
    final data = await batchStorage.fetch(userId: userId, angle: angle);
    if (data != null) {
      await batchStorage.save(
        userId: userId,
        angle: angle,
        data: data.copyWith(
          solved: data.solved.add(solution),
          unsolved: data.unsolved.remove(puzzle),
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

  Future<PuzzleBatch?> _syncAndLoadData(UserId? userId, PuzzleAngle angle) async {
    final data = await batchStorage.fetch(userId: userId, angle: angle);
    final unsolved = data?.unsolved ?? IList(const []);
    final solved = data?.solved ?? IList(const []);

    if (unsolved.length >= queueLength) {
      return data;
    }

    final puzzles = await offlineRepository.selectPuzzles(
      angle: angle,
      limit: queueLength - unsolved.length,
      offset: unsolved.length + solved.length,
    );
    final newBatch = PuzzleBatch(
      solved: IList(const []),
      unsolved: IList([...unsolved, ...puzzles]),
    );
    await batchStorage.save(userId: userId, angle: angle, data: newBatch);
    return newBatch;
  }
}
