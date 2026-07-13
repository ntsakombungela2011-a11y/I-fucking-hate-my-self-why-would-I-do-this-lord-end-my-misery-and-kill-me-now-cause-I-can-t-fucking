# Diagnostic Report: Broken Puzzles in Puzzle Streak/Storm/Themes

## 1. Executive Summary & Bug Classification
This is a **validation-gap/format-mismatch bug** between the curation script (`scripts/curate_puzzle_data.py`) and the mobile app's chessground UI/controller logic.
- **Why it is NOT a column-mapping/parsing bug:** The CSV columns in `curate_puzzle_data.py` are dynamically resolved by headers (`header.index("FEN")`, etc.), which correctly align with the Lichess puzzle CSV schema (`PuzzleId,FEN,Moves,Rating,...`).
- **Why it is NOT a filtering-gap bug:** The starting position of every puzzle in `assets/puzzles.db` is legal, and none are checkmate.

---

## 2. Root Cause Analysis & Detailed Mechanics
In Lichess's raw/online puzzle format (used by the standard Lichess API):
- **Starting FEN:** Represents the position **before** the opponent's first move (`moves[0]`).
- **Moves Sequence:** Includes the opponent's first move (`moves[0]`), followed by the player's response (`moves[1]`), opponent's second move (`moves[2]`), and so on.

However, the curation script `scripts/curate_puzzle_data.py` performs a transformation when generating `assets/puzzles.db`:
1. It pushes the first move `moves[0]` onto the board to generate a play-from position FEN (`new_fen`).
2. It writes `new_fen` to the `fen` column of `puzzles.db`.
3. It strips `moves[0]` and writes only the remaining sequence `moves[1:]` (starting with the player's first move) to the `moves` column in `puzzles.db`.

Meanwhile, the mobile app's UI controllers (`PuzzleController`, `StormController`, etc.) expect the raw/online format. When the App loads a puzzle:
1. It interprets the database FEN (which is already after `moves[0]`) as the starting position.
2. It plays the first move of the database's moves sequence (which is `moves[1]`, the player's first move) **automatically** as if it were the opponent's first move `moves[0]`.
3. This shifts the entire game state forward by one ply in error.

### Resulting Symptoms:
- **Symptom 1 (Checkmate/Terminal Positions with 0 legal moves):** For puzzles that are originally 2 moves long (opponent `moves[0]`, player `moves[1]`), the database stores a 1-move solution (`moves[1]`). When loaded, the computer automatically plays `moves[1]` (which is often a checkmate), leaving no more moves to play. Since the puzzle was not yet completed (no user move entered), the user is left stuck with a board that is already checkmate, presenting an unsolvable puzzle.
- **Symptom 2 (Legal moves escaping check rejected as "not the move"):** For multi-move puzzles, because the computer automatically plays the player's moves, the user is forced to play the opponent's responses. If the player's move checked the user, the user is placed in check. Any legal move to escape check is rejected as "not the move" because the controller only accepts the exact opponent move in the database.

---

## 3. Quantitative Evidence from the Database
We performed a full diagnostic run on all **50,000** puzzles in `assets/puzzles.db` using `python-chess`:
- **Total rows analyzed:** 50,000
- **Legal & Valid starting positions:** 50,000 (100% pass - no corrupt boards, no checkmates in the database FENs).
- **Starting FEN already checkmate:** 0 rows.
- **Rows with exactly 1 move in the `moves` column:** **5,309 rows** (10.6%)
  - *These 5,309 puzzles are completely unsolvable.* When loaded, the computer plays the only move, delivering checkmate/terminal state and locking the board.
- **Rows with 3 or more moves:** **44,691 rows** (89.4%)
  - *These 44,691 puzzles are playable but buggy.* The user is forced to play the opponent's side with a flipped perspective, and their own moves are played by the computer.
- **Conclusion:** **100% of the 50,000 puzzles in the current database are broken** due to this format mismatch!

---

## 4. Proposed Minimal Fixes

### Option A: Fix in Curation Script + Regenerate DB (Recommended)
Modify `curate_puzzle_data.py` to keep the original FEN and full moves list (untransformed), matching the Lichess API structure that the App expects:
```python
# Keep original FEN and original full moves sequence
valid[puzzle_id] = {"fen": fen, "moves": moves_str}
```
And trigger the `.github/workflows/curate-puzzle-data.yml` workflow (or run it via script) to regenerate a correct `assets/puzzles.db`.
- **Pros:** Cleanest, zero Dart code changes, zero runtime overhead, matches the intended design of the App, fully preserves opponent move animation and orientation.
- **Cons:** Requires committing a new 13.3MB binary file to git or downloading the Lichess CSV.

### Option B: Fix in Dart Code (Alternative)
Modify `PuzzleController._loadNewContext` and `StormController` to accommodate the play-from position directly.
For `PuzzleController._loadNewContext`:
If the puzzle is offline, bypass the `_firstMoveTimer`, set `initialPath = UciPath.empty`, and start directly in play mode so the user plays the first move (`solution.first`) themselves.
- **Pros:** No changes required to `assets/puzzles.db` or python scripts; tiny textual code diff in git.
- **Cons:** Worse UX (opponent's first move `moves[0]` is not animated on screen, so the user has to guess what the opponent just played).

---

*Report compiled by Jules.*
