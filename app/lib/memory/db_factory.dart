/// REAL: Platform SQLite database-factory hook for [MemoryStore].
///
/// `package:sqflite_common` (the pure-Dart core of sqflite) requires its
/// global [databaseFactory] to be initialized before `openDatabase` works.
/// In Flutter builds the factory comes from the sqflite platform plugin;
/// in pure-Dart runs there is no plugin, so the hook is a no-op and
/// [MemoryStore.open] fails with a clear error telling the user to run
/// with mocks (or add sqflite_ffi).
///
/// The conditional import keeps `package:sqflite` (which needs `dart:ui`)
/// out of the compile graph for `dart run`.
import 'db_factory_stub.dart'
    if (dart.library.ui) 'db_factory_flutter.dart' as _impl;

/// REAL: Register the platform database factory when one is available.
/// No-op on pure-Dart runs.
void ensureDatabaseFactory() => _impl.ensureDatabaseFactory();
