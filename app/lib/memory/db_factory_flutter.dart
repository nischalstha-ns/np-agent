import 'package:sqflite/sqflite.dart'
    show databaseFactorySqflitePlugin;
import 'package:sqflite_common/sqflite.dart'
    show databaseFactory, databaseFactoryOrNull;

/// REAL: Flutter database-factory hook — registers the sqflite platform
/// plugin's factory exactly once, so `package:sqflite_common`'s global
/// `openDatabase` works in [MemoryStore.open].
///
/// This file is only compiled when `dart:ui` exists (Flutter builds); see
/// `db_factory.dart`. It is never part of a pure `dart run` compile.
void ensureDatabaseFactory() {
  if (databaseFactoryOrNull == null) {
    databaseFactory = databaseFactorySqflitePlugin;
  }
}
