import 'dart:collection';

import 'package:deep_pick/deep_pick.dart' as deep_pick;

export 'package:deep_pick/deep_pick.dart';

/// Contract for classes that are based on a [Rekord]
///
/// Classes implementing this mixin must provide a [rekord] getter that returns
/// a [Rekord] instance containing the data for that class.
mixin RekordMixin {
  Rekord get rekord;
}

/// A Rekord is a immutable collection of data ([Map] based) which can be accessed via [read] using [deep_pick.Pick] API.
///
/// This pattern allows accessing the data field by field, parsing it lazy.
/// Lazy parsing makes the Rekord robust against API changes. Missing or corrupted fields will only throw when accessed.
/// This is a stark contrast to traditional `.fromJson` parsing, which parses the entire response into a dart object, crashing immediately if the structure does not match. Even when the corrupt parts would not be required for the app to function correctly.
///
/// Example:
/// ```dart
/// class User with RekordMixin {
///   User.fromData(Map<String, Object?> data) : rekord = Rekord(data);
///
///   factory User.fromResponse(http.Response response) {
///     final data = jsonDecode(response.body);
///     return User.fromData(data);
///   }
///
///   factory User.create({
///     String? id,
///     String? name,
///   }) {
///     return User.fromData({
///       if (id != null) 'id': id,
///       if (name != null) 'name': name,
///     });
///   }
///
///   @override
///   final Rekord rekord;
///
///   String get id => rekord.read('id').asStringOrThrow();
///   String get name => rekord.read('name').asStringOrThrow();
///
///   @override
///   String toString() => 'User$rekord';
/// }
/// ```
///
/// The User class can be created from a network response
/// ```dart
/// final response = await http.get('https://api.example.com/user');
/// final user = User.fromResponse(response);
/// ```
///
/// It is especially useful to create the Rekord classes in tests, because only the fields that are actually used in the test need to be provided.
/// ```dart
/// final userEmpty = User.create();
/// final userFull = User.create(
///   id: '123',
///   name: 'John Doe',
/// );
/// ```
///
/// Rekord is actually just a very thing layer on top of [Map&ltString, Object?&gt]. The pattern also works without the Rekord class, but the class provides a few conveniences:
/// - Provides a `read` method that returns a [deep_pick.Pick] instance for accessing values.
/// - Makes the data immutable, making it impossible to accidentally modify the data after creation.
/// - Better handling for nested objects (when they are also Rekord or RekordMixin)
class Rekord {
  final Map<String, Object?> _data;

  /// Creates a new [Rekord] from the provided [data].
  ///
  /// The [data] is processed to ensure all nested [Rekord] and [RekordMixin] objects
  /// are converted to plain maps, and the result is stored immutably.
  Rekord(Map<String, Object?> data) : _data = _processMap(data);

  /// Returns an unmodifiable view of the underlying data map.
  ///
  /// This provides access to the raw data without allowing modifications.
  Map<String, Object?> asMap() {
    bool productionCode = true;
    assert(() {
      productionCode = false;
      return true;
    }());
    if (productionCode) {
      return UnmodifiableMapView<String, Object?>(_data);
    }
    // data is directly visible in the debugger
    final easyToDebugCopy = Map.of(_data);
    return UnmodifiableMapView<String, Object?>(easyToDebugCopy);
  }

  /// Converts all nested [Rekord] and [RekordMixin] objects to plain maps
  static Map<String, Object?> _processMap(Map data) {
    return SplayTreeMap<String, Object?>.fromIterable(
      data.entries,
      key: (entry) => entry.key as String,
      value: (entry) => _processValue(entry.value),
    );
  }

  /// Process a list of values, recursively processing each value
  static List<Object?> _processList(Iterable data) {
    return data.map((e) => _processValue(e)).toList();
  }

  /// Process any value recursively, handling maps, lists, and RekordMixin objects
  static Object? _processValue(Object? value) {
    if (value is Map) {
      return _processMap(value);
    }
    if (value is Iterable) {
      return _processList(value);
    }
    if (value is Rekord) {
      return _processMap(value._data);
    }
    if (value is RekordMixin) {
      return _processMap(value.rekord._data);
    }
    return value;
  }

  /// Returns a [deep_pick.Pick] instance for accessing values from the Rekord.
  ///
  /// Use this to read values from the data using the deep_pick API:
  /// ```dart
  /// final id = rekord.read('id').asStringOrThrow();
  /// final name = rekord.read('user.name').asStringOrNull();
  /// final age = rekord.read('user.age').asIntOrNull();
  /// final tags = rekord.read('tags').asListOrEmpty();
  /// ```
  deep_pick.Pick get read {
    return deep_pick.Pick(_data).withContext('rekord', asMap());
  }

  @override
  String toString() {
    return 'Rekord$_data';
  }
}
