// ignore_for_file: avoid_classes_with_only_static_members

import 'package:sidekick_core/sidekick_core.dart';

/// A Gradle like name matcher that matches camel case names.
class CamelCaseNameMatcher {
  /// Finds the best match for the given [pattern] in the given [candidates].
  ///
  /// Precisely, you can match 'foBa' with 'fooBar'
  ///
  /// Only returns at match if it is the only match. Throws an error when multiple candidates match the pattern.
  static String find(String pattern, List<String> candidates) {
    final matches = candidates
        .where((candidate) => _matches(pattern, candidate))
        .toList();
    if (matches.isEmpty) {
      throw ArgumentError(
        'No candidate matches the pattern $pattern. Candidates: $candidates',
      );
    }
    if (matches.length > 1) {
      final exactMatch = matches.firstOrNullWhere((match) => match == pattern);
      if (exactMatch != null) {
        return exactMatch;
      }

      throw ArgumentError(
        'Multiple candidates match the pattern $pattern: $matches',
      );
    }
    return matches.single;
  }

  /// Returns true if the given [pattern] matches the given [candidate].
  static bool _matches(String pattern, String candidate) {
    int patternIndex = 0;
    int candidateIndex = 0;
    while (patternIndex < pattern.length && candidateIndex < candidate.length) {
      final patternChar = pattern[patternIndex];
      final candidateChar = candidate[candidateIndex];
      if (patternChar == candidateChar) {
        patternIndex++;
        candidateIndex++;
      } else if (candidateChar.isUpperCase) {
        return false;
      } else {
        candidateIndex++;
      }
    }
    return patternIndex == pattern.length;
  }
}
