import 'memory_store.dart';

/// REAL: Typed wrapper over the `user_profile` table.
///
/// Well-known keys are exposed as typed helpers; anything else goes through
/// the generic [get]/[set]. Values are stored as strings; callers encode
/// structured values (e.g. JSON) themselves.
class UserProfileMemory {
  final MemoryStore _store;

  const UserProfileMemory(this._store);

  /// REAL: Returns.
  Future<String?> get(String key) => _store.profileGet(key);

  Future<void> set(String key, String value) =>
      _store.profileSet(key, value);

  /// REAL: The all.
  Future<Map<String, String>> all() => _store.profileAll();

  // --- well-known keys ------------------------------------------------------

  /// REAL: The display name.
  Future<String?> displayName() => get('display_name');
  /// REAL: The set display name.
  Future<void> setDisplayName(String v) => set('display_name', v);

  /// REAL: The timezone.
  Future<String?> timezone() => get('timezone');
  /// REAL: The set timezone.
  Future<void> setTimezone(String v) => set('timezone', v);

  /// REAL: The locale.
  Future<String?> locale() => get('locale');
  /// REAL: The set locale.
  Future<void> setLocale(String v) => set('locale', v);

  /// REAL: The preferred model.
  Future<String?> preferredModel() => get('preferred_model');
  /// REAL: The set preferred model.
  Future<void> setPreferredModel(String v) => set('preferred_model', v);
}
