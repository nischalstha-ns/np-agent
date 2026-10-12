import 'memory_store.dart';

/// Typed wrapper over the `user_profile` table.
///
/// Well-known keys are exposed as typed helpers; anything else goes through
/// the generic [get]/[set]. Values are stored as strings; callers encode
/// structured values (e.g. JSON) themselves.
class UserProfileMemory {
  final MemoryStore _store;

  const UserProfileMemory(this._store);

  Future<String?> get(String key) => _store.profileGet(key);

  Future<void> set(String key, String value) =>
      _store.profileSet(key, value);

  Future<Map<String, String>> all() => _store.profileAll();

  // --- well-known keys ------------------------------------------------------

  Future<String?> displayName() => get('display_name');
  Future<void> setDisplayName(String v) => set('display_name', v);

  Future<String?> timezone() => get('timezone');
  Future<void> setTimezone(String v) => set('timezone', v);

  Future<String?> locale() => get('locale');
  Future<void> setLocale(String v) => set('locale', v);

  Future<String?> preferredModel() => get('preferred_model');
  Future<void> setPreferredModel(String v) => set('preferred_model', v);
}
