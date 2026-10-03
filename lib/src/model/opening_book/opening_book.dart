import 'package:dartchess/dartchess.dart';
import 'package:lichess_mobile/src/db/openings_database.dart';

class OpeningBookOpening {
  const OpeningBookOpening({required this.eco, required this.name});

  final String eco;
  final String name;
}

class OpeningBookMove {
  const OpeningBookMove({
    required this.move,
    required this.san,
    required this.count,
    this.opening,
  });

  final Move move;
  final String san;
  final int count;
  final OpeningBookOpening? opening;
}

class OpeningBook {
  const OpeningBook({required this.opening, required this.moves});

  final OpeningBookOpening? opening;
  final List<OpeningBookMove> moves;
}

OpeningBook buildOpeningBook({
  required List<OpeningBookRow> rows,
  required String currentLine,
  required Position currentPosition,
}) {
  final currentMoves = currentLine.isEmpty ? const <String>[] : currentLine.split(' ');
  final exactRows = <String, OpeningBookRow>{for (final row in rows) row.uci: row};
  final counts = <String, int>{};

  for (final row in rows) {
    final moves = row.uci.split(' ');
    if (moves.length <= currentMoves.length) continue;
    if (currentMoves.isNotEmpty && !row.uci.startsWith('$currentLine ')) continue;

    final nextMove = moves[currentMoves.length];
    counts[nextMove] = (counts[nextMove] ?? 0) + 1;
  }

  final moves = <OpeningBookMove>[];
  for (final entry in counts.entries) {
    final move = Move.parse(entry.key);
    if (move == null || !currentPosition.isLegal(move)) continue;

    try {
      final (_, san) = currentPosition.makeSan(move);
      final row = exactRows[currentLine.isEmpty ? entry.key : '$currentLine ${entry.key}'];
      moves.add(
        OpeningBookMove(
          move: move,
          san: san,
          count: entry.value,
          opening: row == null ? null : OpeningBookOpening(eco: row.eco, name: row.name),
        ),
      );
    } on PlayException {
      continue;
    }
  }

  moves.sort((a, b) => b.count.compareTo(a.count));
  final openingRow = exactRows[currentLine];
  return OpeningBook(
    opening: openingRow == null ? null : OpeningBookOpening(eco: openingRow.eco, name: openingRow.name),
    moves: moves,
  );
}
