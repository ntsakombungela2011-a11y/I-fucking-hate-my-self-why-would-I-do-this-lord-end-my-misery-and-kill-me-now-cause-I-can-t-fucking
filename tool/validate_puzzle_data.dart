import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart';

void main() async {
  var pass = 0;
  var fail = 0;

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    final id = row['id'].toString();
    final fen = row['fen'] as String;
    final moves = (row['moves'] as String)
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty)
        .toList();

    try {
      if (moves.isEmpty) {
        throw const FormatException('empty move list');
      }

      Position position = Chess.fromSetup(Setup.parseFen(fen));
      for (final uci in moves) {
        final move = Move.parse(uci);
        if (move == null || !position.isLegal(move)) {
          throw FormatException('illegal move $uci');
        }
        position = position.play(move);
      }

      // Lichess puzzle rows store FEN before the opponent's first move. The app
      // displays the solve-from position after applying that first move, so emit
      // that start FEN with the remaining solution moves for the shipped DB.
      Position start = Chess.fromSetup(Setup.parseFen(fen));
      final firstMove = Move.parse(moves.first)!;
      start = start.play(firstMove);
      final solution = moves.skip(1).toList(growable: false);
      if (solution.isEmpty) {
        throw const FormatException('missing solution after first move');
      }

      stdout.writeln(jsonEncode({'id': id, 'fen': start.fen, 'moves': solution.join(' ')}));
      pass++;
    } catch (e) {
      stderr.writeln(jsonEncode({'id': id, 'error': e.toString()}));
      fail++;
    }
  }

  stderr.writeln(jsonEncode({'pass': pass, 'fail': fail}));
}
