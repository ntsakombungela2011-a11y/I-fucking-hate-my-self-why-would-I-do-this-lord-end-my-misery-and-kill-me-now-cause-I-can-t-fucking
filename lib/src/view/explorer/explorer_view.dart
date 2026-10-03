import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/opening_service.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/db/openings_database.dart';
import 'package:lichess_mobile/src/model/explorer/tablebase.dart';
import 'package:lichess_mobile/src/model/opening_book/opening_book.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/explorer/opening_explorer_view.dart';
import 'package:lichess_mobile/src/view/explorer/tablebase_view.dart';

/// Unified explorer view that shows either opening explorer or tablebase
/// based on the position state (opening vs endgame)

const kExplorerTableRowVerticalPadding = 10.0;
const kExplorerTableRowHorizontalPadding = 8.0;
const kExplorerTableRowPadding = EdgeInsets.symmetric(
  horizontal: kExplorerTableRowHorizontalPadding,
  vertical: kExplorerTableRowVerticalPadding,
);
const kHeaderTextStyle = TextStyle(fontSize: 12);

Color whiteBoxColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.8)
    : Colors.white;

Color blackBoxColor(BuildContext context) => Theme.of(context).brightness == Brightness.light
    ? Colors.black.withValues(alpha: 0.7)
    : Colors.black;

/// Resolves the [Opening] to display in the opening explorer, or `null` when
/// the variant has no opening book.
///
/// Falls back to the deepest ancestor opening ([branchOpening]) when the current
/// node has no opening of its own.
Opening? explorerOpening(
  BuildContext context, {
  required Variant variant,
  required bool isRootNode,
  required Opening? nodeOpening,
  required Opening? branchOpening,
}) {
  if (!kOpeningAllowedVariants.contains(variant)) return null;
  if (isRootNode) {
    return LightOpening(eco: '', name: context.l10n.startPosition);
  }
  return nodeOpening ?? branchOpening;
}

class ExplorerView extends ConsumerWidget {
  const ExplorerView({
    required this.pov,
    required this.position,
    required this.onMoveSelected,
    required this.isComputerAnalysisAllowed,
    this.opening,
    this.bookLine,
  });

  final Side pov;
  final Position position;
  final bool isComputerAnalysisAllowed;
  final Opening? opening;
  final String? bookLine;
  final void Function(Move) onMoveSelected;

  bool get tablebaseRelevant => isTablebaseRelevant(position);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (position.isCheckmate) {
      return Center(child: Text(context.l10n.checkmate));
    }
    if (position.isStalemate) {
      return Center(child: Text(context.l10n.stalemate));
    }
    if (position.isInsufficientMaterial) {
      return Center(child: Text(context.l10n.insufficientMaterial));
    }

    final isLoggedIn = ref.watch(isLoggedInProvider);
    if (!isLoggedIn) {
      if (bookLine == null) {
        return const Center(child: Text('The opening book is not available for this position.'));
      }

      final rows = ref.watch(openingBookRowsProvider);
      return rows.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => const Center(child: Text('Could not load the opening book.')),
        data: (rows) {
          final book = buildOpeningBook(rows, bookLine!);
          final bookMoves = <_OfflineOpeningBookMove>[];
          for (final bookMove in book.moves) {
            final move = Move.parse(bookMove.uci);
            if (move == null || !position.isLegal(move)) continue;
            try {
              final (_, san) = position.makeSan(move);
              bookMoves.add(_OfflineOpeningBookMove(bookMove: bookMove, move: move, san: san));
            } catch (_) {
              continue;
            }
          }
          return _OfflineOpeningBookView(
            opening: book.opening,
            moves: bookMoves,
            onMoveSelected: onMoveSelected,
          );
        },
      );
    }

    if (tablebaseRelevant && isComputerAnalysisAllowed) {
      return TablebaseView(position: position, onMoveSelected: onMoveSelected);
    }

    return OpeningExplorerView(
      pov: pov,
      shouldDisplayGames: isComputerAnalysisAllowed,
      position: position,
      opening: opening,
      onMoveSelected: onMoveSelected,
    );
  }
}


class _OfflineOpeningBookView extends StatelessWidget {
  const _OfflineOpeningBookView({
    required this.opening,
    required this.moves,
    required this.onMoveSelected,
  });

  final OpeningBookOpening? opening;
  final List<_OfflineOpeningBookMove> moves;
  final void Function(Move) onMoveSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            opening == null
                ? 'No named opening for this position'
                : '${opening!.eco} ${opening!.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Book moves'),
        ),
        if (moves.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No book moves from here.'),
          )
        else
          for (final move in moves)
            ListTile(
              title: Text(move.san),
              subtitle: move.bookMove.opening == null ? null : Text(move.bookMove.opening!.name),
              trailing: Text('${move.bookMove.count} lines'),
              onTap: () => onMoveSelected(move.move),
            ),
      ],
    );
  }
}

class _OfflineOpeningBookMove {
  const _OfflineOpeningBookMove({
    required this.bookMove,
    required this.move,
    required this.san,
  });

  final OpeningBookMove bookMove;
  final Move move;
  final String san;
}
