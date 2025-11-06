/// A beacon that emits null when source data becomes stale.
///
/// This beacon wraps another beacon and automatically emits null if no new data
/// arrives within the specified [stalenessThreshold]. This is useful for sensor
/// data streams where you want to detect when a device stops transmitting
/// (e.g., power meter battery dies, heart rate monitor disconnects).
///
/// Example:
/// ```dart
/// final sensorBeacon = Beacon.writable<int?>(null);
///
/// // Create staleness-aware beacon
/// final staleAware = sensorBeacon.withStalenessDetection(
///   threshold: Duration(seconds: 5),
/// );
///
/// // Or use constructor directly
/// final staleAware = StalenessBeacon(
///   sensorBeacon,
///   Duration(seconds: 5),
/// );
///
/// // When data arrives, it's immediately available
/// sensorBeacon.value = 100;
/// print(staleAware.value); // 100
///
/// // After 5 seconds with no new data, value becomes null
/// await Future.delayed(Duration(seconds: 5, milliseconds: 100));
/// print(staleAware.value); // null
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:state_beacon/state_beacon.dart';

/// A beacon that emits null when the source beacon's data becomes stale.
///
/// Subscribes to a source beacon and forwards data immediately. If no new
/// data arrives within [stalenessThreshold], emits null to indicate stale data.
///
/// This beacon extends [WritableBeacon] and uses manual subscriptions to forward
/// values from the source beacon. When disposed, it automatically cleans up the
/// subscription and any pending staleness timers.
///
/// This is a true custom beacon that extends the beacon class hierarchy,
/// similar to how ThrottledBeacon and BufferedBeacon are implemented in dart_beacon.
class StalenessBeacon<T> extends WritableBeacon<T?> {
  /// Creates a staleness-aware beacon.
  ///
  /// - [source]: The beacon to monitor for staleness
  /// - [stalenessThreshold]: Duration after which data is considered stale
  ///
  /// The beacon starts with a null value and updates whenever the source emits.
  StalenessBeacon(this._source, this._stalenessThreshold) {
    // Subscribe to source and forward values
    _subscription = _source.subscribe(_onData);
  }

  final ReadableBeacon<T?> _source;
  final Duration _stalenessThreshold;

  Timer? _stalenessTimer;
  VoidCallback? _subscription;

  void _onData(T? data) {
    // Cancel existing timer
    _stalenessTimer?.cancel();

    // Set the new value using the public API (this notifies observers)
    value = data;

    // Only start timer for non-null data
    if (data != null) {
      _stalenessTimer = Timer(_stalenessThreshold, () {
        // Set to null after staleness threshold (this notifies observers)
        value = null;
      });
    }
  }

  @override
  void dispose() {
    // Clean up subscription and timer before disposing
    _subscription?.call();
    _subscription = null;
    _stalenessTimer?.cancel();
    _stalenessTimer = null;

    // Call parent dispose to clean up beacon resources
    super.dispose();
  }
}

/// Extension methods for adding staleness detection to beacons.
extension StalenessBeaconExtension<T> on ReadableBeacon<T?> {
  /// Creates a new beacon that emits null when this beacon's data becomes stale.
  ///
  /// Returns a new [StalenessBeacon] that forwards data from this beacon
  /// immediately, but emits null if no new data arrives within [threshold].
  ///
  /// Example:
  /// ```dart
  /// final sensor = Beacon.writable<PowerData?>(null);
  /// final staleAware = sensor.withStalenessDetection(
  ///   threshold: Duration(seconds: 5),
  /// );
  ///
  /// // Can be chained with other transforms
  /// final processed = sensor
  ///   .withStalenessDetection(threshold: Duration(seconds: 5))
  ///   .map((data) => data?.watts ?? 0);
  /// ```
  StalenessBeacon<T> withStalenessDetection({required Duration threshold}) {
    return StalenessBeacon(this, threshold);
  }
}
