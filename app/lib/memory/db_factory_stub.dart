/// REAL: Pure-Dart database-factory hook — intentionally a no-op.
///
/// There is no sqflite platform plugin in a pure-Dart VM, so
/// [MemoryStore.open] cannot work here; it will throw sqflite_common's
/// "databaseFactory not initialized" StateError. Use
/// `NpCore.initialize(useMocks: true)` (the default) for pure-Dart runs.
void ensureDatabaseFactory() {}
