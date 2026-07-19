import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/puzzles_database.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:sqflite/sqflite.dart';

final offlinePuzzleRepositoryProvider = FutureProvider<OfflinePuzzleRepository>((Ref ref) async {
  final database = await ref.watch(puzzlesDatabaseProvider.future);
  return OfflinePuzzleRepository(database);
}, name: 'OfflinePuzzleRepositoryProvider');

class OfflinePuzzleRepository {
  const OfflinePuzzleRepository(this._db);

  final Database _db;

  Future<IList<Puzzle>> randomPuzzles({
    required int limit,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
  }) async {
    final rows = switch (angle) {
      PuzzleTheme(themeKey: PuzzleThemeKey.mix) => await _db.rawQuery(
        'SELECT id, fen, moves, rating, popularity FROM puzzles ORDER BY RANDOM() LIMIT ?',
        [limit],
      ),
      PuzzleTheme(themeKey: final themeKey) => await _db.rawQuery(
        '''
        SELECT p.id, p.fen, p.moves, p.rating, p.popularity
        FROM puzzles p
        INNER JOIN puzzle_themes pt ON pt.puzzle_id = p.id
        INNER JOIN themes t ON t.id = pt.theme_id
        WHERE t.name = ?
        ORDER BY RANDOM()
        LIMIT ?
        ''',
        [themeKey.name, limit],
      ),
      PuzzleOpening() => const <Map<String, Object?>>[],
    };

    final puzzles = <Puzzle>[];
    for (final row in rows) {
      final themes = await _themesForPuzzle(row['id']! as int);
      puzzles.add(_puzzleFromRow(row, themes));
    }
    return puzzles.lock;
  }

  Future<IList<LitePuzzle>> randomLitePuzzles({required int limit}) async {
    final firstRow = await _db.rawQuery(
      'SELECT id, fen, moves, rating FROM puzzles ORDER BY RANDOM() LIMIT 1',
    );
    if (firstRow.isEmpty) {
      return const IList.empty();
    }
    final firstFen = firstRow.first['fen']! as String;
    final isWhite = firstFen.contains(' w ');
    final sidePattern = isWhite ? '% w %' : '% b %';

    final remainingRows = await _db.rawQuery(
      'SELECT id, fen, moves, rating FROM puzzles WHERE fen LIKE ? AND id != ? ORDER BY RANDOM() LIMIT ?',
      [sidePattern, firstRow.first['id']! as int, limit - 1],
    );

    final allRows = [...firstRow, ...remainingRows];
    return allRows.map(_litePuzzleFromRow).toIList();
  }

  Future<IMap<PuzzleThemeKey, int>> themeCounts() async {
    final rows = await _db.rawQuery('''
      SELECT t.name, COUNT(pt.puzzle_id) AS count
      FROM themes t
      LEFT JOIN puzzle_themes pt ON pt.theme_id = t.id
      GROUP BY t.id, t.name
    ''');

    return rows.fold<IMap<PuzzleThemeKey, int>>(IMap(const {}), (acc, row) {
      final key = puzzleThemeNameMap[row['name']! as String];
      if (key == null) return acc;
      return acc.add(key, row['count']! as int);
    });
  }

  Future<ISet<String>> _themesForPuzzle(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT t.name
      FROM themes t
      INNER JOIN puzzle_themes pt ON pt.theme_id = t.id
      WHERE pt.puzzle_id = ?
      ''',
      [id],
    );
    return rows.map((row) => row['name']! as String).toSet().lock;
  }

  Puzzle _puzzleFromRow(Map<String, Object?> row, ISet<String> themes) {
    final id = row['id']! as int;
    final fen = row['fen']! as String;
    final moves = (row['moves']! as String).split(' ');
    final firstMove = Move.parse(moves.first)!;
    final position = Chess.fromSetup(Setup.parseFen(fen));
    final (_, san) = position.makeSan(firstMove);

    return Puzzle(
      puzzle: PuzzleData(
        id: PuzzleId(id.toString()),
        rating: row['rating']! as int,
        plays: row['popularity']! as int,
        initialPly: _plyFromFen(fen),
        solution: moves.skip(1).toIList(),
        themes: themes,
      ),
      game: PuzzleGame(
        id: GameId(id.toRadixString(36).padLeft(8, '0')),
        perf: Perf.puzzle,
        rated: false,
        white: const PuzzleGamePlayer(side: Side.white, name: 'Offline'),
        black: const PuzzleGamePlayer(side: Side.black, name: 'Offline'),
        pgn: '[FEN "$fen"]\n\n$san',
      ),
    );
  }

  LitePuzzle _litePuzzleFromRow(Map<String, Object?> row) {
    return LitePuzzle(
      id: PuzzleId((row['id']! as int).toString()),
      fen: row['fen']! as String,
      solution: (row['moves']! as String).split(' ').toIList(),
      rating: row['rating']! as int,
    );
  }

  int _plyFromFen(String fen) {
    final parts = fen.split(' ');
    final fullMove = int.parse(parts[5]);
    return (fullMove - 1) * 2 + (parts[1] == 'b' ? 1 : 0);
  }
}
