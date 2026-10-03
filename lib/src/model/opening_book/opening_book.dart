import 'package:lichess_mobile/src/db/openings_database.dart';

class OpeningBookOpening {
  const OpeningBookOpening({required this.eco, required this.name});

  final String eco;
  final String name;
}

class OpeningBookMove {
  const OpeningBookMove({
    required this.uci,
    required this.count,
    this.opening,
  });

  final String uci;
  final int count;
  final OpeningBookOpening? opening;
}

class OpeningBook {
  const OpeningBook({required this.opening, required this.moves});

  final OpeningBookOpening? opening;
  final List<OpeningBookMove> moves;
}

OpeningBook buildOpeningBook(List<OpeningBookRow> rows, String currentLine) {
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
    final row = exactRows[currentLine.isEmpty ? entry.key : '$currentLine ${entry.key}'];
    moves.add(
      OpeningBookMove(
        uci: entry.key,
        count: entry.value,
        opening: row == null ? null : OpeningBookOpening(eco: row.eco, name: row.name),
      ),
    );
  }

  moves.sort((a, b) => b.count.compareTo(a.count));
  final openingRow = exactRows[currentLine];
  return OpeningBook(
    opening: openingRow == null ? null : OpeningBookOpening(eco: openingRow.eco, name: openingRow.name),
    moves: moves,
  );
}
