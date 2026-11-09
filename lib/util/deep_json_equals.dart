/// Linear-time structural equality for JSON-shaped data (maps, lists,
/// scalars).
///
/// Use this instead of `package:collection`'s [DeepCollectionEquality] for
/// Mod state, configs, and link values. `MapEquality.equals` builds a
/// `HashMap` whose entry hash codes deep-hash entire subtrees, so every
/// nesting level re-traverses everything below it. On large Mod states that
/// turned "microseconds" dedup checks into multi-second main-thread stalls
/// (see test-results/pathologicalDeepEquality.json). This walk is O(n) with
/// `identical` fast paths and no hashing of composite values.
///
/// Ordering tuned via test/perf/deep_json_equals_perf_test.dart: scalars
/// exit first (leaves outnumber containers ~7:1, and String.== already
/// begins with an identical check, so the outer `identical` stub was pure
/// overhead for them); maps iterate `entries` (one hash lookup into `b`
/// beat keys+double-lookup by ~30%).
bool deepJsonEquals(Object? a, Object? b) {
  if (a is String || a is num || a is bool) return a == b;
  if (identical(a, b)) return true;
  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final entry in a.entries) {
      final theirs = b[entry.key];
      if (theirs == null && !b.containsKey(entry.key)) return false;
      if (!deepJsonEquals(entry.value, theirs)) return false;
    }
    return true;
  }
  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (!deepJsonEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

/// Reuses containers from [previous] wherever [next] has equal JSON content.
///
/// The returned root is [previous] when both trees are deeply equal. For a
/// partial change, [next] remains the root but equal descendant maps/lists are
/// replaced in-place with their [previous] instances. This gives declarative
/// consumers structural sharing after a JSON/worker boundary without hashing
/// subtrees or walking the data twice.
///
/// Both inputs must be acyclic JSON-shaped values. [next] maps and lists must
/// be mutable when they contain descendants that can be shared.
Object? reuseDeepJsonIdentities(Object? previous, Object? next) {
  if (previous is String || previous is num || previous is bool) {
    return previous == next ? previous : next;
  }
  if (identical(previous, next)) return previous;
  if (previous is Map && next is Map) {
    var unchanged = previous.length == next.length;
    for (final entry in next.entries) {
      if (!previous.containsKey(entry.key)) {
        unchanged = false;
        continue;
      }
      final previousValue = previous[entry.key];
      final shared = reuseDeepJsonIdentities(previousValue, entry.value);
      if (!identical(shared, entry.value)) next[entry.key] = shared;
      if (!identical(shared, previousValue)) unchanged = false;
    }
    return unchanged ? previous : next;
  }
  if (previous is List && next is List) {
    var unchanged = previous.length == next.length;
    final sharedLength = previous.length < next.length
        ? previous.length
        : next.length;
    for (var index = 0; index < sharedLength; index += 1) {
      final shared = reuseDeepJsonIdentities(previous[index], next[index]);
      if (!identical(shared, next[index])) next[index] = shared;
      if (!identical(shared, previous[index])) unchanged = false;
    }
    return unchanged ? previous : next;
  }
  return previous == next ? previous : next;
}

/// Linear structural hash consistent with [deepJsonEquals].
///
/// Lists are order-sensitive. Maps are order-independent: entry hashes are
/// summed, not fed into a sequence hash. This is intended for immutable
/// JSON-shaped value objects that need both `==` and `hashCode`; equality-only
/// hot paths should call [deepJsonEquals] and avoid hashing entirely.
int deepJsonHash(Object? value) {
  if (value is String || value is num || value is bool) return value.hashCode;
  if (value == null) return null.hashCode;
  if (value is List) {
    var hash = Object.hash(_kListHashMarker, value.length);
    for (final element in value) {
      hash = Object.hash(hash, deepJsonHash(element));
    }
    return hash;
  }
  if (value is Map) {
    var entriesHash = 0;
    for (final entry in value.entries) {
      entriesHash =
          (entriesHash +
              Object.hash(deepJsonHash(entry.key), deepJsonHash(entry.value))) &
          0x3fffffff;
    }
    return Object.hash(_kMapHashMarker, value.length, entriesHash);
  }
  return value.hashCode;
}

const _kListHashMarker = 0x4c495354; // "LIST"
const _kMapHashMarker = 0x4d415020; // "MAP "
