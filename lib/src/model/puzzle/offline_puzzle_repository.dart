import 'dart:io';

import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const _kDatabaseVersion = 1;
const _kDatabaseName = 'puzzles$_kDatabaseVersion.db';
const _kPuzzleAssetPgnPrefix = 'fen:';

final offlinePuzzleDatabaseProvider = FutureProvider<Database>((Ref ref) async {
  final dbPath = p.join(await getDatabasesPath(), _kDatabaseName);
  return _openDb(dbPath);
}, name: 'OfflinePuzzleDatabaseProvider');

final offlinePuzzleRepositoryProvider = FutureProvider<OfflinePuzzleRepository>((Ref ref) async {
  return OfflinePuzzleRepository(await ref.watch(offlinePuzzleDatabaseProvider.future));
}, name: 'OfflinePuzzleRepositoryProvider');

Future<Database> _openDb(String path) async {
  final exists = await databaseExists(path);

  if (!exists) {
    final directory = Directory(p.dirname(path));

    try {
      await directory.create(recursive: true);
    } catch (_) {}

    directory.list().forEach((file) {
      if (p.basename(file.path).startsWith('puzzles')) {
        deleteDatabase(file.path);
      }
    });

    final ByteData data = await rootBundle.load(p.url.join('assets', 'puzzles.db'));
    final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    await File(path).writeAsBytes(bytes, flush: true);
  }

  return databaseFactory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
}

class OfflinePuzzleRepository {
  const OfflinePuzzleRepository(this._db);

  final Database _db;

  Future<IList<Puzzle>> selectPuzzles({
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT p.id, p.fen, p.moves, p.rating, p.popularity, group_concat(t.name) AS themes
      FROM puzzles p
      JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      JOIN themes t ON t.id = pt.theme_id
      ${angle.key == PuzzleThemeKey.mix.name ? '' : 'WHERE p.id IN (SELECT puzzle_id FROM puzzle_themes JOIN themes ON themes.id = theme_id WHERE themes.name = ?)'}
      GROUP BY p.id
      ORDER BY p.id
      LIMIT ? OFFSET ?
      ''', [
      if (angle.key != PuzzleThemeKey.mix.name) angle.key,
      limit,
      offset,
    ]);

    return rows.map(_puzzleFromRow).toIList();
  }

  Future<Puzzle?> fetch(PuzzleId puzzleId) async {
    final rows = await _db.rawQuery('''
      SELECT p.id, p.fen, p.moves, p.rating, p.popularity, group_concat(t.name) AS themes
      FROM puzzles p
      JOIN puzzle_themes pt ON pt.puzzle_id = p.id
      JOIN themes t ON t.id = pt.theme_id
      WHERE p.id = ?
      GROUP BY p.id
      LIMIT 1
      ''', [int.tryParse(puzzleId.value) ?? -1]);
    return rows.isEmpty ? null : _puzzleFromRow(rows.first);
  }

  Future<IMap<PuzzleThemeKey, int>> themeCounts() async {
    final rows = await _db.rawQuery('''
      SELECT t.name, count(*) AS count
      FROM themes t
      JOIN puzzle_themes pt ON pt.theme_id = t.id
      GROUP BY t.name
      ''');
    final counts = <PuzzleThemeKey, int>{};
    for (final row in rows) {
      final key = puzzleThemeNameMap[row['name'] as String];
      if (key != null) counts[key] = row['count'] as int;
    }
    return counts.lock;
  }

  Puzzle _puzzleFromRow(Map<String, Object?> row) {
    final id = row['id'] as int;
    final fen = row['fen'] as String;
    final solution = (row['moves'] as String).split(' ').where((move) => move.isNotEmpty).toIList();
    final themes = ((row['themes'] as String?) ?? '')
        .split(',')
        .where((theme) => theme.isNotEmpty)
        .toSet()
        .lock;
    final setup = Setup.parseFen(fen);
    final position = Chess.fromSetup(setup);

    return Puzzle(
      puzzle: PuzzleData(
        id: PuzzleId(id.toString()),
        rating: row['rating'] as int,
        plays: row['popularity'] as int,
        initialPly: position.ply,
        solution: solution,
        themes: themes,
      ),
      game: PuzzleGame(
        id: GameId(id.toString().padLeft(8, '0')),
        perf: Perf.rapid,
        rated: false,
        white: const PuzzleGamePlayer(side: Side.white, name: 'Offline'),
        black: const PuzzleGamePlayer(side: Side.black, name: 'Offline'),
        pgn: '$_kPuzzleAssetPgnPrefix$fen',
      ),
    );
  }
}

bool isOfflinePuzzleAssetPgn(String pgn) => pgn.startsWith(_kPuzzleAssetPgnPrefix);
String offlinePuzzleAssetFen(String pgn) => pgn.substring(_kPuzzleAssetPgnPrefix.length);
