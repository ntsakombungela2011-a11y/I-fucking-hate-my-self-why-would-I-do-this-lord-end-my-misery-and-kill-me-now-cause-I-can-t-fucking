import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const _kDatabaseVersion = 1;
const _kDatabaseName = 'puzzles$_kDatabaseVersion.db';

/// A provider for the bundled offline puzzles database.
final puzzlesDatabaseProvider = FutureProvider<Database>((Ref ref) async {
  final dbPath = p.join(await getDatabasesPath(), _kDatabaseName);
  return _openDb(dbPath);
}, name: 'PuzzlesDatabaseProvider');

Future<Database> _openDb(String path) async {
  final exists = await databaseExists(path);

  if (!exists) {
    final directory = Directory(p.dirname(path));

    try {
      await directory.create(recursive: true);
    } catch (_) {}

    directory.list().forEach((file) {
      if (file.path.startsWith('puzzles')) {
        deleteDatabase(file.path);
      }
    });

    final ByteData data = await rootBundle.load(p.url.join('assets', 'puzzles.db'));
    final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    await File(path).writeAsBytes(bytes, flush: true);
  }

  return databaseFactory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
}
