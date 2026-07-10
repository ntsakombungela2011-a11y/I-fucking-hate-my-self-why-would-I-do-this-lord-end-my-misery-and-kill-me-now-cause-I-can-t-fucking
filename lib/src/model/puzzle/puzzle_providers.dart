import "package:lichess_mobile/src/model/puzzle/procedural_generator.dart";
import 'package:dartchess/dartchess.dart';
import 'dart:math';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_batch_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_opening.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_repository.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_service.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_storage.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/model/puzzle/storm.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/utils/riverpod.dart';

/// Fetches the next puzzle for the given [PuzzleAngle].
final nextPuzzleProvider = FutureProvider.autoDispose
    .family<PuzzleContext?, PuzzleAngle>((Ref ref, PuzzleAngle angle) async {
      final authUser = ref.watch(authControllerProvider);
      final puzzleService = await ref.read(puzzleServiceFactoryProvider)(
        queueLength: kPuzzleLocalQueueLength,
      );
      // useful for for preview puzzle list in puzzle tab (providers in a list can
      // be invalidated multiple times when the user scrolls the list)
      ref.cacheFor(const Duration(minutes: 1));

      return puzzleService.nextPuzzle(userId: authUser?.user.id, angle: angle);
    }, name: 'NextPuzzleProvider');

/// Fetches the list of puzzles to replay for the given number of [days] and [theme].
final puzzleReplayProvider = FutureProvider.autoDispose
    .family<PuzzleContext?, ({int days, String theme})>((
      Ref ref,
      ({int days, String theme}) params,
    ) async {
      final authUser = ref.watch(authControllerProvider);
      if (authUser == null) return null;
      final repo = ref.read(puzzleRepositoryProvider);
      final remaining = await repo.puzzleReplay(params.days, params.theme);
      if (remaining.isEmpty) return null;
      final puzzle = await repo.fetch(remaining.first);
      return PuzzleContext(
        puzzle: puzzle,
        angle: const PuzzleTheme(PuzzleThemeKey.mix),
        userId: authUser.user.id,
        replayRemaining: remaining.removeAt(0),
      );
    }, name: 'PuzzleReplayProvider');

/// Fetches a storm of puzzles.
final stormProvider = FutureProvider.autoDispose<PuzzleStormResponse>((
  Ref ref,
) {
  final List<LitePuzzle> litePuzzles = [];
  final Set<String> seenIds = {};

  // Initialize with 10 puzzles, and the StormController look-ahead buffer will dynamically refill indefinitely
  for (int i = 0; i < 10; i++) {
    Puzzle puzzle;
    while (true) {
      puzzle = ProceduralPuzzleGenerator.generatePuzzle(PuzzleThemeKey.mix);
      if (!seenIds.contains(puzzle.puzzle.id.value)) {
        seenIds.add(puzzle.puzzle.id.value);
        break;
      }
    }

    final root = Root.fromPgnMoves(puzzle.game.pgn);
    final node = root.nodeAt(root.mainlinePath);
    final fen = node.position.fen;

    litePuzzles.add(
      LitePuzzle(
        id: puzzle.puzzle.id,
        fen: fen,
        solution: puzzle.puzzle.solution,
        rating: puzzle.puzzle.rating,
      ),
    );
  }

  return PuzzleStormResponse(
    puzzles: IList(litePuzzles),
    key: 'offline-storm-key',
    highscore: const PuzzleStormHighScore(
      allTime: 0,
      day: 0,
      month: 0,
      week: 0,
    ),
    timestamp: DateTime.now(),
  );
}, name: 'StormProvider');

/// Fetches a puzzle from the local storage if available, otherwise fetches it from the server.
final puzzleProvider = FutureProvider.autoDispose.family<Puzzle, PuzzleId>((
  Ref ref,
  PuzzleId id,
) async {
  final puzzleStorage = await ref.watch(puzzleStorageProvider.future);
  final puzzle = await puzzleStorage.fetch(puzzleId: id);
  if (puzzle != null) return puzzle;
  return ref.read(puzzleRepositoryProvider).fetch(id);
}, name: 'PuzzleProvider');

/// Fetches the daily puzzle.
final dailyPuzzleProvider = FutureProvider.autoDispose<Puzzle>((Ref ref) {
  return ref.withClientCacheFor(
    (client) => PuzzleRepository(client).daily(),
    const Duration(hours: 6),
  );
}, name: 'DailyPuzzleProvider');

/// Saves/gets saved puzzle batches for the current user.
final savedBatchesProvider =
    FutureProvider.autoDispose<IList<(PuzzleAngle, int)>>((Ref ref) async {
      final authUser = ref.watch(authControllerProvider);
      final storage = await ref.watch(puzzleBatchStorageProvider.future);
      return storage.fetchAll(userId: authUser?.user.id);
    }, name: 'SavedBatchesProvider');

/// Fetches saved puzzle theme batches for the current user.
final savedThemeBatchesProvider =
    FutureProvider.autoDispose<IMap<PuzzleThemeKey, int>>((Ref ref) async {
      final authUser = ref.watch(authControllerProvider);
      final storage = await ref.watch(puzzleBatchStorageProvider.future);
      return storage.fetchSavedThemes(userId: authUser?.user.id);
    }, name: 'SavedThemeBatchesProvider');

/// Fetches saved puzzle opening batches for the current user.
final savedOpeningBatchesProvider =
    FutureProvider.autoDispose<IMap<String, int>>((Ref ref) async {
      final authUser = ref.watch(authControllerProvider);
      final storage = await ref.watch(puzzleBatchStorageProvider.future);
      return storage.fetchSavedOpenings(userId: authUser?.user.id);
    }, name: 'SavedOpeningBatchesProvider');

/// Fetches the puzzle dashboard for the current user for the given number of [days].
final puzzleDashboardProvider = FutureProvider.autoDispose
    .family<PuzzleDashboard?, int>((Ref ref, int days) {
      final authUser = ref.watch(authControllerProvider);
      if (authUser == null) return null;
      return ref.watch(puzzleRepositoryProvider).puzzleDashboard(days);
    }, name: 'PuzzleDashboardProvider');

/// Fetches recent puzzle activity for the current user.
final puzzleRecentActivityProvider =
    FutureProvider.autoDispose<IList<PuzzleHistoryEntry>?>((Ref ref) {
      final authUser = ref.watch(authControllerProvider);
      if (authUser == null) return null;
      return ref.watch(puzzleRepositoryProvider).puzzleActivity(20);
    }, name: 'PuzzleRecentActivityProvider');

/// Saves/gets the high score and history for the given user [UserId].
final stormDashboardProvider = FutureProvider.autoDispose
    .family<StormDashboard?, UserId>((Ref ref, UserId id) {
      return ref.read(puzzleRepositoryProvider).stormDashboard(id);
    }, name: 'StormDashboardProvider');

/// Fetches available puzzle themes.
final puzzleThemesProvider =
    FutureProvider.autoDispose<IMap<PuzzleThemeKey, PuzzleThemeData>>((
      Ref ref,
    ) {
      return ref.withClientCacheFor(
        (client) => PuzzleRepository(client).puzzleThemes(),
        const Duration(days: 1),
      );
    }, name: 'PuzzleThemesProvider');

/// Fetches available puzzle openings.
final puzzleOpeningsProvider = FutureProvider.autoDispose
    .family<IList<PuzzleOpeningFamily>, PuzzleOpeningSort>((
      Ref ref,
      PuzzleOpeningSort sort,
    ) {
      return ref.withClientCacheFor(
        (client) => PuzzleRepository(
          client,
        ).puzzleOpenings(alphabetical: sort == PuzzleOpeningSort.alphabetical),
        const Duration(days: 1),
      );
    }, name: 'PuzzleOpeningsProvider');
