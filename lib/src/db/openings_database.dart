import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/debug/startup_trace.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// The dataset is from https://github.com/lichess-org/chess-openings
// It can be updated by running the script at scripts/update_openings_db.py

const _kDatabaseVersion = 5;
const _kDatabaseName = 'chess_openings$_kDatabaseVersion.db';

/// A provider for the openings database.
final openingsDatabaseProvider = FutureProvider<Database>((Ref ref) async {
  final dbPath = p.join(await getDatabasesPath(), _kDatabaseName);
  return _openDb(dbPath);
}, name: 'OpeningsDatabaseProvider');

typedef OpeningBookRow = ({String eco, String name, String uci});

/// Loads the bundled opening-book rows once for the offline explorer.
Future<List<OpeningBookRow>> readOpeningBookRows(Database database) async {
  final rows = await database.rawQuery('SELECT eco, name, uci FROM openings');
  return rows
      .map(
        (row) => (
          eco: row['eco']! as String,
          name: row['name']! as String,
          uci: row['uci']! as String,
        ),
      )
      .toList();
}

final openingBookRowsProvider = FutureProvider<List<OpeningBookRow>>((Ref ref) async {
  final database = await ref.watch(openingsDatabaseProvider.future);
  return readOpeningBookRows(database);
}, name: 'OpeningBookRowsProvider');

Future<Database> _openDb(String path) async {
  final exists = await databaseExists(path);

  if (!exists) {
    final directory = Directory(p.dirname(path));

    // Make sure the parent directory exists
    try {
      await directory.create(recursive: true);
    } catch (_) {}

    // Delete existing previous if any
    directory.list().forEach((file) {
      if (file.path.startsWith('chess_openings')) {
        deleteDatabase(file.path);
      }
    });

    // Copy from asset
    final ByteData data = await rootBundle.load(p.url.join('assets', 'chess_openings.db'));
    final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    // Write and flush the bytes written
    await File(path).writeAsBytes(bytes, flush: true);
  }

  StartupTrace.mark('openings db open start');
  return databaseFactory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true)).then((db) {
    StartupTrace.mark('openings db open end');
    return db;
  });
}
