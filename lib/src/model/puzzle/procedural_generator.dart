import 'dart:math';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';

class ProceduralPuzzleSeed {
  final String id;
  final List<String> moves;
  final List<String> solution;
  final int rating;
  final Set<String> themes;

  const ProceduralPuzzleSeed({
    required this.id,
    required this.moves,
    required this.solution,
    required this.rating,
    required this.themes,
  });
}

class ProceduralPuzzleGenerator {
  static const List<ProceduralPuzzleSeed> _seeds = [
    ProceduralPuzzleSeed(
      id: "scholars_mate",
      moves: ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6'],
      solution: ['h5f7'],
      rating: 800,
      themes: {'mate', 'mateIn1', 'attackingF2F7', 'opening', 'equality'},
    ),
    ProceduralPuzzleSeed(
      id: "legalls_mate",
      moves: ['e2e4', 'e7e5', 'g1f3', 'd7d6', 'f1c4', 'c8g4', 'b1c3', 'g7g6', 'f3e5', 'g4d1'],
      solution: ['c4f7', 'e8e7', 'c3d5'],
      rating: 1100,
      themes: {'mate', 'mateIn2', 'sacrifice', 'discoveredAttack', 'opening', 'crushing'},
    ),
    ProceduralPuzzleSeed(
      id: "philidor_smothered",
      moves: [
        'e2e4',
        'e7e5',
        'g1f3',
        'b8c6',
        'f1c4',
        'c6d4',
        'f3e5',
        'd8g5',
        'e5f7',
        'g5g2',
        'h1f1',
        'g2e4',
        'c4e2',
        'd4f3',
      ],
      solution: ['d4f3'],
      rating: 1300,
      themes: {'mate', 'mateIn1', 'smotheredMate', 'fork', 'opening', 'crushing'},
    ),
    ProceduralPuzzleSeed(
      id: "en_passant",
      moves: ['e2e4', 'e7e6', 'e4e5', 'd7d5'],
      solution: ['e5d6'],
      rating: 1000,
      themes: {'enPassant', 'discoveredAttack', 'opening', 'equality'},
    ),
    ProceduralPuzzleSeed(
      id: "queen_fork",
      moves: [
        'e2e4',
        'e7e5',
        'g1f3',
        'b8c6',
        'b1c3',
        'g8f6',
        'f1b5',
        'a7a6',
        'b5c6',
        'd7c6',
        'f3e5',
        'f6e4',
        'c3e4',
        'd8d4',
      ],
      solution: ['d8d4', 'e1g1', 'd4e5'],
      rating: 1100,
      themes: {'fork', 'short', 'advantage', 'opening'},
    ),
    ProceduralPuzzleSeed(
      id: "carokann_smothered",
      moves: ['e2e4', 'c7c6', 'd2d4', 'd7d5', 'b1c3', 'd5e4', 'c3e4', 'b8d7', 'd1e2', 'g8f6'],
      solution: ['e4d6'],
      rating: 950,
      themes: {'mate', 'mateIn1', 'smotheredMate', 'pin', 'opening', 'crushing'},
    ),
    ProceduralPuzzleSeed(
      id: "lasker_trap",
      moves: [
        'd2d4',
        'd7d5',
        'c2c4',
        'e7e5',
        'd4e5',
        'd5d4',
        'e2e3',
        'f8b4',
        'c1d2',
        'd4e3',
        'd2b4',
        'e3f2',
        'e1e2',
      ],
      solution: ['f2g1n'],
      rating: 1500,
      themes: {
        'underPromotion',
        'promotion',
        'discoveredAttack',
        'sacrifice',
        'opening',
        'crushing',
      },
    ),
    ProceduralPuzzleSeed(
      id: "danish_castling",
      moves: [
        'e2e4',
        'e7e5',
        'g1f3',
        'b8c6',
        'd2d4',
        'e5d4',
        'c2c3',
        'd4c3',
        'f1c4',
        'c3b2',
        'c1b2',
        'f8b4',
        'b1d2',
        'g8f6',
        'd1b3',
        'e8g8',
      ],
      solution: ['e1g1'],
      rating: 1050,
      themes: {'castling', 'pin', 'opening', 'equality'},
    ),
    ProceduralPuzzleSeed(
      id: "ruy_lopez_noah_ark",
      moves: [
        'e2e4',
        'e7e5',
        'g1f3',
        'b8c6',
        'f1b5',
        'a7a6',
        'b5a4',
        'd7d6',
        'd2d4',
        'b7b5',
        'a4b3',
        'c6d4',
        'f3d4',
        'e5d4',
        'd1d4',
        'c7c5',
        'd4d5',
        'c8e6',
        'd5c6',
      ],
      solution: ['e6d7', 'c6d5', 'c5c4'],
      rating: 1200,
      themes: {'trappedPiece', 'queensideAttack', 'opening', 'advantage'},
    ),
  ];

  static List<ProceduralPuzzleSeed> get seeds => _seeds;

  static final List<String> _playerNames = [
    'Kasparov',
    'Carlsen',
    'Fischer',
    'Boipelo',
    'Anand',
    'Karpov',
    'Capablanca',
    'Alekhine',
    'Tal',
    'Spassky',
    'Petrosian',
    'Botvinnik',
    'Smyslov',
    'Euwe',
    'Lasker',
    'Steinitz',
    'Nakamura',
    'Caruana',
    'Ding',
    'Nepomniachtchi',
    'Firouzja',
    'Praggnanandhaa',
    'Gukesh',
    'Keymer',
    'Abdusattorov',
    'So',
    'Giri',
    'Aronian',
    'Radjabov',
    'Mamedyarov',
    'Topalov',
    'Kramnik',
    'Shirov',
    'Ivanchuk',
    'Gelfand',
    'Svidler',
    'Adams',
    'Short',
    'Chigorin',
    'Tarrasch',
    'Marshall',
    'Rubinstein',
    'Nimzowitsch',
    'Reti',
    'Spielmann',
    'Tartakower',
    'Maroczy',
    'Janowsky',
    'Schlechter',
    'Pillsbury',
    'Tschigorin',
    'Blackburne',
    'Zukertort',
  ];

  static String _mirrorUciHorizontal(String uci) {
    final fromFile = uci[0];
    final fromRank = uci[1];
    final toFile = uci[2];
    final toRank = uci[3];
    final promo = uci.length > 4 ? uci[4] : "";

    final mirroredFromFile = String.fromCharCode(201 - fromFile.codeUnitAt(0));
    final mirroredToFile = String.fromCharCode(201 - toFile.codeUnitAt(0));

    return mirroredFromFile + fromRank + mirroredToFile + toRank + promo;
  }

  static Puzzle generatePuzzle(PuzzleThemeKey themeKey) {
    final rand = Random();

    // Loop until we find a 100% verified, legal puzzle
    while (true) {
      try {
        // Filter seeds matching requested theme
        List<ProceduralPuzzleSeed> matching = [];
        if (themeKey == PuzzleThemeKey.mix) {
          matching = _seeds;
        } else {
          final nameStr = themeKey.name;
          matching = _seeds.where((s) => s.themes.contains(nameStr)).toList();
          if (matching.isEmpty) {
            matching = _seeds;
          }
        }

        final seed = matching[rand.nextInt(matching.length)];

        // Verify legality of all moves and solution step-by-step
        Position pos = Position.initialPosition(Rule.chess);
        List<String> sanMoves = [];
        bool allMovesLegal = true;

        for (final uci in seed.moves) {
          final moveObj = Move.parse(uci);
          if (moveObj == null || !pos.isLegal(moveObj)) {
            allMovesLegal = false;
            break;
          }
          final (_, san) = pos.makeSan(moveObj);
          sanMoves.add(san);
          pos = pos.play(moveObj);
        }

        if (!allMovesLegal) {
          continue; // Discard and try another seed
        }

        // Also verify legality of solution moves
        Position solPos = pos;
        for (final uci in seed.solution) {
          final moveObj = Move.parse(uci);
          if (moveObj == null || !solPos.isLegal(moveObj)) {
            allMovesLegal = false;
            break;
          }
          solPos = solPos.play(moveObj);
        }

        if (!allMovesLegal) {
          continue; // Discard and try another seed
        }

        // Puzzle is 100% legal and verified! Build and return it.
        final puzzleIdStr = "proc_" + seed.id + "_" + rand.nextInt(100000).toString();
        final int ratingJitter = rand.nextInt(101) - 50; // Jitter of +-50
        final finalRating = (seed.rating + ratingJitter).clamp(600, 2800);

        final p1 = _playerNames[rand.nextInt(_playerNames.length)];
        var p2 = _playerNames[rand.nextInt(_playerNames.length)];
        while (p1 == p2) {
          p2 = _playerNames[rand.nextInt(_playerNames.length)];
        }

        final pgnString = sanMoves.join(' ');
        final Set<String> finalThemes = Set.from(seed.themes);

        // Classification 1: Group 4 (Phases)
        final int pieceCount = _countPieces(pos);
        if (pieceCount <= 6) {
          finalThemes.add('endgame');
        } else if (seed.moves.length <= 16) {
          finalThemes.add('opening');
        } else {
          finalThemes.add('middlegame');
        }

        return Puzzle(
          puzzle: PuzzleData(
            id: PuzzleId(puzzleIdStr),
            rating: finalRating,
            plays: rand.nextInt(5000) + 1500,
            initialPly: seed.moves.length,
            solution: seed.solution.lock,
            themes: finalThemes.toISet(),
          ),
          game: PuzzleGame(
            id: GameId(puzzleIdStr.substring(0, min(puzzleIdStr.length, 8)).padRight(8, '0')),
            perf: Perf.puzzle,
            rated: false,
            white: PuzzleGamePlayer(side: Side.white, name: p1),
            black: PuzzleGamePlayer(side: Side.black, name: p2),
            pgn: pgnString,
          ),
        );
      } catch (e) {
        debugPrint('Silently discarding corrupt procedural puzzle: ');
        continue;
      }
    }
  }

  static int _countPieces(Position pos) {
    int count = 0;
    for (final (_, piece) in pos.board.pieces) {
      if (piece.role != Role.king) {
        count++;
      }
    }
    return count;
  }

  static bool _hasPieceType(Position pos, Role role) {
    for (final (_, piece) in pos.board.pieces) {
      if (piece.role == role) {
        return true;
      }
    }
    return false;
  }
}
