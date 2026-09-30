import 'package:dartchess/dartchess.dart';

/// Computes the set of squares that should have an atomic explosion animation
/// after [move] was played from [positionBefore].
///
/// Returns `null` if [positionBefore] is not an atomic position, [move] is
/// null, or the move was not a capture (no explosion occurs).
Set<Square>? atomicExplosionSquares(Position positionBefore, Move? move) {
  if (move == null || positionBefore is! Atomic) return null;
  final squareSet = positionBefore.explosionSquares(move);
  return squareSet.isEmpty ? null : squareSet.squares.toSet();
}
