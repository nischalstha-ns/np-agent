/// REAL: Minimal service-locator DI container.
///
/// Singletons are registered eagerly with [register] or lazily with
/// [registerLazy] (created on first [get], then cached). There is one
/// container per [NpCore] instance, built in `NpCore.initialize()`.
class ServiceLocator {
  final Map<Type, Object> _singletons = {};
  final Map<Type, Object Function()> _factories = {};

  /// REAL: Register an already-built instance.
  void register<T extends Object>(T instance) {
    _singletons[T] = instance;
  }

  /// REAL: Register a factory; the instance is built on first [get] and cached.
  void registerLazy<T extends Object>(T Function() factory) {
    _factories[T] = factory;
  }

  bool has<T extends Object>() =>
      _singletons.containsKey(T) || _factories.containsKey(T);

  /// REAL: Resolve [T]. Throws [StateError] when nothing is registered.
  T get<T extends Object>() {
    /// REAL: The existing.
    final existing = _singletons[T];
    if (existing != null) return existing as T;
    /// REAL: The factory.
    final factory = _factories[T];
    if (factory == null) {
      throw StateError('DI: no registration found for type $T');
    }
    /// REAL: The created.
    final created = factory() as T;
    _singletons[T] = created;
    return created;
  }

  /// REAL: Resolve [T], or return null when nothing is registered.
  T? tryGet<T extends Object>() => has<T>() ? get<T>() : null;

  /// REAL: Drop every registration (used in tests / on shutdown).
  void reset() {
    _singletons.clear();
    _factories.clear();
  }
}
