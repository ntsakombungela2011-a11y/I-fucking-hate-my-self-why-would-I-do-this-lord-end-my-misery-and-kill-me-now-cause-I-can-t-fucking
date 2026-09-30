#!/usr/bin/env python3
"""Curate a static SQLite puzzle database from the Lichess open puzzle CSV.

Input CSV schema is documented by Lichess as:
PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sqlite3
import subprocess
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable

import chess

CURATED_THEME_MAP = {
    "fork": {"fork"},
    "pin": {"pin"},
    "skewer": {"skewer"},
    "discoveredAttack": {"discoveredAttack"},
    "deflection": {"deflection"},
    "sacrifice": {"sacrifice"},
    "hangingPiece": {"hangingPiece"},
    "trappedPiece": {"trappedPiece"},
    "promotion": {"promotion", "underPromotion"},
    "enPassant": {"enPassant"},
    "mateIn1": {"mateIn1"},
    "mateIn2": {"mateIn2"},
    "mateIn3": {"mateIn3"},
    "mateIn4": {"mateIn4"},
    "mateIn5": {"mateIn5"},
    "backRankMate": {"backRankMate"},
    "smotheredMate": {"smotheredMate"},
    "endgame": {"endgame"},
    "middlegame": {"middlegame"},
    "opening": {"opening"},
}

RATING_BANDS = [
    (0, 999),
    (1000, 1199),
    (1200, 1399),
    (1400, 1599),
    (1600, 1799),
    (1800, 1999),
    (2000, 2199),
    (2200, 2399),
    (2400, 9999),
]


def percentile(values: list[int], pct: float) -> int:
    if not values:
        return 0
    values = sorted(values)
    index = min(len(values) - 1, max(0, math.ceil((pct / 100) * len(values)) - 1))
    return values[index]


def band_for(rating: int) -> str:
    for lo, hi in RATING_BANDS:
        if lo <= rating <= hi:
            return f"{lo}-{hi if hi < 9999 else 'max'}"
    return "unknown"


def curated_categories(raw_themes: str) -> list[str]:
    raw = set(raw_themes.split())
    categories = [name for name, tags in CURATED_THEME_MAP.items() if raw & tags]
    return categories


def validate_with_python_chess(
    rows: list[dict[str, object]]
) -> tuple[dict[str, dict[str, str]], int, int]:
    valid: dict[str, dict[str, str]] = {}
    pass_count = 0
    fail_count = 0
    for row in rows:
        puzzle_id = str(row["id"])
        fen = str(row["fen"])
        moves_str = str(row["moves"])
        moves = moves_str.split()
        try:
            if len(moves) < 2:
                raise ValueError("missing solution after first move")
            
            # 1. Full validation of the moves sequence (fast and robust)
            board = chess.Board(fen)
            for m_uci in moves:
                m = chess.Move.from_uci(m_uci)
                if m not in board.legal_moves:
                    raise ValueError(f"illegal move {m_uci}")
                board.push(m)
            
            # 2. Preserve the raw Lichess puzzle format: FEN before the
            # opponent's first move, followed by the full UCI move sequence.
            valid[puzzle_id] = {"fen": fen, "moves": moves_str}
            pass_count += 1
        except Exception as e:
            fail_count += 1
            
    return valid, pass_count, fail_count


def validate_with_dart(
    rows: list[dict[str, object]], validator: str
) -> tuple[dict[str, dict[str, str]], int, int]:
    proc = subprocess.Popen(
        validator,
        shell=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.stdin is not None
    for row in rows:
        proc.stdin.write(
            json.dumps({"id": row["id"], "fen": row["fen"], "moves": row["moves"]}) + "\n"
        )
    proc.stdin.close()

    valid: dict[str, dict[str, str]] = {}
    assert proc.stdout is not None
    for line in proc.stdout:
        data = json.loads(line)
        valid[data["id"]] = {"fen": data["fen"], "moves": data["moves"]}

    stderr = proc.stderr.read() if proc.stderr is not None else ""
    code = proc.wait()
    if code != 0:
        raise RuntimeError(f"validator exited {code}: {stderr}")

    pass_count = len(valid)
    fail_count = 0
    for line in stderr.splitlines():
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "pass" in data and "fail" in data:
            pass_count = int(data["pass"])
            fail_count = int(data["fail"])
    return valid, pass_count, fail_count


def write_sqlite(db_path: Path, rows: list[dict[str, object]]) -> None:
    if db_path.exists():
        db_path.unlink()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path)
    try:
        con.executescript(
            """
            PRAGMA journal_mode=OFF;
            CREATE TABLE puzzles(
              id INTEGER PRIMARY KEY,
              fen TEXT NOT NULL,
              moves TEXT NOT NULL,
              rating INTEGER NOT NULL,
              popularity INTEGER NOT NULL
            );
            CREATE TABLE themes(
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL UNIQUE
            );
            CREATE TABLE puzzle_themes(
              puzzle_id INTEGER NOT NULL REFERENCES puzzles(id),
              theme_id INTEGER NOT NULL REFERENCES themes(id),
              PRIMARY KEY (puzzle_id, theme_id)
            );
            CREATE INDEX puzzles_rating_idx ON puzzles(rating);
            CREATE INDEX puzzle_themes_theme_id_idx ON puzzle_themes(theme_id);
            """
        )
        theme_ids: dict[str, int] = {}
        next_theme_id = 1
        for row in rows:
            con.execute(
                "INSERT INTO puzzles(id, fen, moves, rating, popularity) VALUES (?, ?, ?, ?, ?)",
                (
                    row["int_id"],
                    row["validated_fen"],
                    row["validated_moves"],
                    row["rating"],
                    row["popularity"],
                ),
            )
            for theme in row["themes"]:
                if theme not in theme_ids:
                    theme_ids[theme] = next_theme_id
                    con.execute("INSERT INTO themes(id, name) VALUES (?, ?)", (next_theme_id, theme))
                    next_theme_id += 1
                con.execute(
                    "INSERT INTO puzzle_themes(puzzle_id, theme_id) VALUES (?, ?)",
                    (row["int_id"], theme_ids[theme]),
                )
        con.commit()
        con.execute("VACUUM")
    finally:
        con.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--validator", default=None)
    parser.add_argument("--target", type=int, default=100_000)
    parser.add_argument("--sample-limit", type=int)
    parser.add_argument("--min-popularity", type=int)
    parser.add_argument("--min-nb-plays", type=int)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    popularity_values: list[int] = []
    nb_plays_values: list[int] = []
    scanned = 0
    skipped_empty_themes = 0

    # Fast first pass using csv.reader to gather distribution stats and scanned totals
    with args.input.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
            col_themes = header.index("Themes")
            col_popularity = header.index("Popularity")
            col_nb_plays = header.index("NbPlays")
            col_rating = header.index("Rating")
        except (ValueError, IndexError) as e:
            raise RuntimeError(f"Invalid input CSV schema: {e}")

        for i, row_cells in enumerate(reader):
            if args.sample_limit is not None and i >= args.sample_limit:
                break
            scanned += 1
            try:
                themes_raw = row_cells[col_themes].strip()
                if not themes_raw:
                    skipped_empty_themes += 1
                    continue
                popularity = int(row_cells[col_popularity])
                nb_plays = int(row_cells[col_nb_plays])
                _ = int(row_cells[col_rating])
                popularity_values.append(popularity)
                nb_plays_values.append(nb_plays)
            except (IndexError, ValueError):
                continue

    # Empirical thresholds: start from the observed candidate distribution and
    # keep the upper-quality half, but never below practical floors. This is
    # reported by the workflow summary and can be overridden manually.
    min_popularity = (
        args.min_popularity
        if args.min_popularity is not None
        else max(50, percentile(popularity_values, 50))
    )
    min_nb_plays = (
        args.min_nb_plays
        if args.min_nb_plays is not None
        else max(50, percentile(nb_plays_values, 50))
    )

    candidate_rows: list[dict[str, object]] = []
    skipped_unmapped_themes = 0
    skipped_short_moves = 0

    # Second pass: stream, filter, and extract candidate details efficiently
    with args.input.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        col_puzzle_id = header.index("PuzzleId")
        col_fen = header.index("FEN")
        col_moves = header.index("Moves")
        col_rating = header.index("Rating")
        col_popularity = header.index("Popularity")
        col_nb_plays = header.index("NbPlays")
        col_themes = header.index("Themes")

        for i, row_cells in enumerate(reader):
            if args.sample_limit is not None and i >= args.sample_limit:
                break
            try:
                popularity = int(row_cells[col_popularity])
                nb_plays = int(row_cells[col_nb_plays])
                
                # Filter early to keep memory consumption low
                if popularity < min_popularity or nb_plays < min_nb_plays:
                    continue

                themes_raw = row_cells[col_themes].strip()
                if not themes_raw:
                    continue

                moves_str = row_cells[col_moves]
                if len(moves_str.split()) < 2:
                    skipped_short_moves += 1
                    continue

                themes = curated_categories(themes_raw)
                if not themes:
                    skipped_unmapped_themes += 1
                    continue

                rating = int(row_cells[col_rating])
                candidate_rows.append(
                    {
                        "id": row_cells[col_puzzle_id],
                        "fen": row_cells[col_fen],
                        "moves": moves_str,
                        "rating": rating,
                        "popularity": popularity,
                        "nb_plays": nb_plays,
                        "raw_themes": themes_raw.split(),
                        "themes": list(dict.fromkeys(themes_raw.split() + themes)),
                        "curated_themes": themes,
                        "band": band_for(rating),
                    }
                )
            except (IndexError, ValueError):
                continue

    by_band: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in candidate_rows:
        by_band[str(row["band"])].append(row)
    for rows in by_band.values():
        rows.sort(
            key=lambda r: (
                int(r["popularity"]),
                int(r["nb_plays"]),
                -abs(int(r["rating"]) - 1600),
            ),
            reverse=True,
        )

    selected: list[dict[str, object]] = []
    per_band = max(1, args.target // max(1, len(RATING_BANDS)))
    for lo, hi in RATING_BANDS:
        name = f"{lo}-{hi if hi < 9999 else 'max'}"
        selected.extend(by_band[name][:per_band])

    if len(selected) < args.target:
        selected_ids = {row["id"] for row in selected}
        remainder = [row for row in candidate_rows if row["id"] not in selected_ids]
        remainder.sort(key=lambda r: (int(r["popularity"]), int(r["nb_plays"])), reverse=True)
        selected.extend(remainder[: args.target - len(selected)])
    selected = selected[: args.target]

    if args.validator:
        valid, pass_count, fail_count = validate_with_dart(selected, args.validator)
    else:
        valid, pass_count, fail_count = validate_with_python_chess(selected)

    survivors: list[dict[str, object]] = []
    for idx, row in enumerate(selected, start=1):
        if row["id"] not in valid:
            continue
        row = dict(row)
        row["int_id"] = idx
        row["validated_fen"] = valid[str(row["id"])]["fen"]
        row["validated_moves"] = valid[str(row["id"])]["moves"]
        survivors.append(row)

    write_sqlite(args.output, survivors)
    asset_size = args.output.stat().st_size

    report = {
        "source": "Lichess open puzzle database, CC0",
        "scanned": scanned,
        "empty_themes_dropped": skipped_empty_themes,
        "unmapped_themes_dropped": skipped_unmapped_themes,
        "short_moves_dropped": skipped_short_moves,
        "popularity_distribution": {
            "min": min(popularity_values) if popularity_values else None,
            "p50": percentile(popularity_values, 50),
            "p75": percentile(popularity_values, 75),
            "p90": percentile(popularity_values, 90),
            "max": max(popularity_values) if popularity_values else None,
        },
        "nb_plays_distribution": {
            "min": min(nb_plays_values) if nb_plays_values else None,
            "p50": percentile(nb_plays_values, 50),
            "p75": percentile(nb_plays_values, 75),
            "p90": percentile(nb_plays_values, 90),
            "max": max(nb_plays_values) if nb_plays_values else None,
        },
        "min_popularity": min_popularity,
        "min_nb_plays": min_nb_plays,
        "target": args.target,
        "selected_before_validation": len(selected),
        "validation_pass": pass_count,
        "validation_fail": fail_count,
        "final_pool_size": len(survivors),
        "asset_size_bytes": asset_size,
        "rating_bands": Counter(str(row["band"]) for row in survivors),
        "curated_theme_map": {k: sorted(v) for k, v in CURATED_THEME_MAP.items()},
        "fen_handling": "Preserved the original Lichess FEN and full Moves string; moves[0] remains the opponent's first move.",
    }
    text = json.dumps(report, indent=2, sort_keys=True)
    print(text)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
