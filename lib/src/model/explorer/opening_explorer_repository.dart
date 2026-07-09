import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:lichess_mobile/src/db/openings_database.dart';
import 'package:lichess_mobile/src/model/common/chess.dart' show Variant, LightOpening;
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/explorer/opening_explorer.dart';
import 'package:lichess_mobile/src/model/explorer/opening_explorer_preferences.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/utils/riverpod.dart';
import 'package:sqflite/sqflite.dart';

final openingExplorerProvider = AsyncNotifierProvider.autoDispose
    .family<
      OpeningExplorer,
      ({OpeningExplorerEntry entry, bool isIndexing})?,
      ({String fen, Variant variant})
    >((request) => OpeningExplorer(request.fen, request.variant), name: 'OpeningExplorerProvider');

class OpeningExplorer extends AsyncNotifier<({OpeningExplorerEntry entry, bool isIndexing})?> {
  OpeningExplorer(this.fen, this.variant);

  final String fen;
  final Variant variant;

  StreamSubscription<OpeningExplorerEntry>? _openingExplorerSubscription;

  @override
  Future<({OpeningExplorerEntry entry, bool isIndexing})?> build() async {
    ref.onDispose(() {
      _openingExplorerSubscription?.cancel();
    });

    await ref.debounce(const Duration(milliseconds: 300));

    try {
      final db = await ref.read(openingsDatabaseProvider.future);
      final epd = '${fen.split(' - ')[0]} -';

      // Check if starting position
      final isStartingPosition = epd.startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');

      String baseUci = '';
      String? currentOpeningName;
      String? currentEco;

      if (!isStartingPosition) {
        final list = await db.query('openings', where: 'epd = ?', whereArgs: [epd], limit: 1);
        final first = list.firstOrNull;
        if (first != null) {
          baseUci = first['uci']! as String;
          currentOpeningName = first['name']! as String;
          currentEco = first['eco']! as String;
        } else {
          // Out of book
          return (
            entry: const OpeningExplorerEntry(
              white: 0,
              draws: 0,
              black: 0,
              moves: IListConst([]),
              opening: null,
            ),
            isIndexing: false,
          );
        }
      }

      List<Map<String, dynamic>> lines;
      int baseUciSplitLength = 0;

      if (baseUci.isEmpty) {
        lines = await db.query('openings', where: "uci NOT LIKE '% %'");
        baseUciSplitLength = 0;
      } else {
        lines = await db.query('openings', where: 'uci LIKE ?', whereArgs: ['$baseUci %']);
        baseUciSplitLength = baseUci.split(' ').length;
      }

      // Aggregate next moves
      final Map<String, int> moveCounts = {};
      final Map<String, String> moveOpeningNames = {};
      final Map<String, String> moveEcos = {};

      for (final row in lines) {
        final uci = row['uci']! as String;
        final parts = uci.split(' ');
        if (parts.length > baseUciSplitLength) {
          final nextMoveUci = parts[baseUciSplitLength];
          moveCounts[nextMoveUci] = (moveCounts[nextMoveUci] ?? 0) + 1;

          // Store opening name and ECO for this move (leads to the most specific sub-line)
          final name = row['name']! as String;
          final eco = row['eco']! as String;
          moveOpeningNames[nextMoveUci] = name;
          moveEcos[nextMoveUci] = eco;
        }
      }

      // Build the list of OpeningMove objects using real chess logic for SAN
      final Position currentPosition = Position.setupPosition(variant.rule, Setup.parseFen(fen));
      final List<OpeningMove> movesList = [];

      for (final nextMoveUci in moveCounts.keys) {
        final moveObj = Move.parse(nextMoveUci);
        if (moveObj != null) {
          // Verify legality of the move
          final isLegal = currentPosition.isLegal(moveObj);
          if (isLegal) {
            final (_, sanStr) = currentPosition.makeSan(moveObj);
            final int count = moveCounts[nextMoveUci]!;

            // Distribute popularity count among white/draw/black to show in popularity bar
            // Let's divide count as white: count, draws: 0, black: 0 to keep it mathematically honest!
            movesList.add(
              OpeningMove(uci: nextMoveUci, san: sanStr, white: count, draws: 0, black: 0),
            );
          }
        }
      }

      // Sort moves by popularity (descending)
      movesList.sort((a, b) => b.games.compareTo(a.games));

      // Calculate total wins/draws/losses for the position
      int totalWhite = 0;
      for (final m in movesList) {
        totalWhite += m.white;
      }

      final LightOpening? currentOpening = currentOpeningName != null
          ? LightOpening(eco: currentEco ?? '', name: currentOpeningName)
          : null;

      return (
        entry: OpeningExplorerEntry(
          white: totalWhite,
          draws: 0,
          black: 0,
          moves: IList(movesList),
          opening: currentOpening,
        ),
        isIndexing: false,
      );
    } catch (e, stackTrace) {
      debugPrint('Error loading offline openings: $e\\n$stackTrace');
      return (
        entry: const OpeningExplorerEntry(
          white: 0,
          draws: 0,
          black: 0,
          moves: IListConst([]),
          opening: null,
        ),
        isIndexing: false,
      );
    }
  }
}

/// A provider for [OpeningExplorerRepository].
final openingExplorerRepositoryProvider = Provider<OpeningExplorerRepository>((Ref ref) {
  return OpeningExplorerRepository(ref.watch(lichessClientProvider));
}, name: 'OpeningExplorerRepositoryProvider');

Uri _explorerUri(String path, [Map<String, dynamic>? queryParameters]) =>
    kLichessOpeningExplorerHost.startsWith('localhost') ||
        kLichessOpeningExplorerHost.startsWith('10.') ||
        kLichessOpeningExplorerHost.startsWith('192.168.')
    ? Uri.http(kLichessOpeningExplorerHost, path, queryParameters)
    : Uri.https(kLichessOpeningExplorerHost, path, queryParameters);

class OpeningExplorerRepository {
  const OpeningExplorerRepository(this.client);

  final Client client;

  Future<OpeningExplorerEntry> getMasterDatabase(String fen, {int? since}) {
    return client.readJson(
      _explorerUri('/masters', {
        'source': 'mobile',
        'fen': fen,
        if (since != null) 'since': since.toString(),
      }),
      mapper: OpeningExplorerEntry.fromJson,
    );
  }

  Future<OpeningExplorerEntry> getLichessDatabase(
    String fen, {
    required Variant variant,
    required ISet<Speed> speeds,
    required ISet<int> ratings,
    DateTime? since,
  }) {
    return client.readJson(
      _explorerUri('/lichess', {
        'source': 'mobile',
        'variant': _openingExplorerVariantKey(variant),
        'fen': fen,
        if (speeds.isNotEmpty) 'speeds': speeds.map((speed) => speed.name).join(','),
        if (ratings.isNotEmpty) 'ratings': ratings.join(','),
        if (since != null) 'since': '${since.year}-${since.month}',
      }),
      mapper: OpeningExplorerEntry.fromJson,
    );
  }

  Future<Stream<OpeningExplorerEntry>> getPlayerDatabase(
    String fen, {
    required Variant variant,
    required String usernameOrId,
    required Side color,
    required ISet<Speed> speeds,
    required ISet<GameMode> gameModes,
    DateTime? since,
  }) {
    return client.readNdJsonStream(
      _explorerUri('/player', {
        'source': 'mobile',
        'variant': _openingExplorerVariantKey(variant),
        'fen': fen,
        'player': usernameOrId,
        'color': color.name,
        if (speeds.isNotEmpty) 'speeds': speeds.map((speed) => speed.name).join(','),
        if (gameModes.isNotEmpty) 'modes': gameModes.map((gameMode) => gameMode.name).join(','),
        if (since != null) 'since': '${since.year}-${since.month}',
      }),
      mapper: OpeningExplorerEntry.fromJson,
    );
  }
}

// Opening explorer treats imported/custom positions as standard chess.
// Other variants must be explicit or the API falls back to standard data.
String _openingExplorerVariantKey(Variant variant) =>
    variant == Variant.fromPosition ? Variant.standard.name : variant.name;

OpeningDatabase _openingExplorerDatabaseFor(OpeningDatabase db, Variant variant) {
  // The masters endpoint has no variant parameter. For variants, fall back to
  // Lichess DB instead of asking users to change their persisted setting.
  if (db == OpeningDatabase.master &&
      variant != Variant.standard &&
      variant != Variant.fromPosition) {
    return OpeningDatabase.lichess;
  }
  return db;
}
