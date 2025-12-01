/// Power history tracking for workout visualization.
///
/// Tracks power data points at regular intervals for display in the
/// workout player's wattage bars visualization.
library;

/// A single power data point at a specific time.
class PowerDataPoint {
  /// Creates a power data point.
  const PowerDataPoint({required this.timestamp, required this.actualWatts, required this.targetWatts});

  /// Timestamp of the data point (milliseconds since workout start).
  final int timestamp;

  /// Actual power output in watts.
  final int actualWatts;

  /// Target power in watts at this time.
  final int targetWatts;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PowerDataPoint &&
        other.timestamp == timestamp &&
        other.actualWatts == actualWatts &&
        other.targetWatts == targetWatts;
  }

  @override
  int get hashCode => Object.hash(timestamp, actualWatts, targetWatts);

  @override
  String toString() {
    return 'PowerDataPoint(timestamp: ${timestamp}ms, actual: ${actualWatts}W, target: ${targetWatts}W)';
  }
}

/// Manages power history for workout visualization.
///
/// Collects power data points at regular intervals (default 15 seconds)
/// for display in the wattage bars chart. Maintains a rolling window
/// of data points to avoid unbounded memory growth.
class PowerHistory {
  /// Creates a power history tracker.
  ///
  /// - [intervalMs] - Time between data points in milliseconds (default 15000 = 15s)
  /// - [maxDataPoints] - Maximum number of data points to keep (default 120 = 30 minutes at 15s intervals)
  PowerHistory({this.intervalMs = 15000, this.maxDataPoints = 120});

  /// Interval between data points in milliseconds.
  final int intervalMs;

  /// Maximum number of data points to keep in history.
  final int maxDataPoints;

  /// List of power data points, ordered by timestamp (oldest first).
  final List<PowerDataPoint> _dataPoints = [];

  /// Timestamp of the last recorded data point.
  int? _lastRecordedTimestamp;

  /// All data points in the history.
  List<PowerDataPoint> get dataPoints => List.unmodifiable(_dataPoints);

  /// Number of data points currently in history.
  int get length => _dataPoints.length;

  /// Whether the history is empty.
  bool get isEmpty => _dataPoints.isEmpty;

  /// Whether the history is not empty.
  bool get isNotEmpty => _dataPoints.isNotEmpty;

  /// Records a new power data point.
  ///
  /// Only records if enough time has elapsed since the last data point
  /// (based on [intervalMs]). If the history exceeds [maxDataPoints],
  /// the oldest data point is removed.
  ///
  /// Returns true if the data point was recorded, false if skipped.
  bool record({required int timestamp, required int actualWatts, required int targetWatts}) {
    // Check if we should record based on interval
    if (_lastRecordedTimestamp != null) {
      final timeSinceLastRecord = timestamp - _lastRecordedTimestamp!;
      if (timeSinceLastRecord < intervalMs) {
        return false; // Too soon, skip
      }
    }

    // Create and add data point
    final dataPoint = PowerDataPoint(timestamp: timestamp, actualWatts: actualWatts, targetWatts: targetWatts);
    _dataPoints.add(dataPoint);
    _lastRecordedTimestamp = timestamp;

    // Enforce max data points limit (FIFO)
    if (_dataPoints.length > maxDataPoints) {
      _dataPoints.removeAt(0);
    }

    return true;
  }

  /// Gets the most recent data point, or null if history is empty.
  PowerDataPoint? get latest => _dataPoints.isEmpty ? null : _dataPoints.last;

  /// Gets data points within a specific time range.
  ///
  /// Returns all data points where timestamp is >= [startMs] and < [endMs].
  List<PowerDataPoint> getRange({required int startMs, required int endMs}) {
    return _dataPoints.where((point) => point.timestamp >= startMs && point.timestamp < endMs).toList();
  }

  /// Gets the last N data points.
  ///
  /// If N is greater than the number of available points, returns all points.
  List<PowerDataPoint> getLastN(int n) {
    if (n >= _dataPoints.length) {
      return List.unmodifiable(_dataPoints);
    }
    return List.unmodifiable(_dataPoints.sublist(_dataPoints.length - n));
  }

  /// Clears all data points from history.
  void clear() {
    _dataPoints.clear();
    _lastRecordedTimestamp = null;
  }

  /// Gets the average actual power across all data points.
  ///
  /// Returns null if history is empty.
  double? get averageActualPower {
    if (_dataPoints.isEmpty) return null;
    final sum = _dataPoints.fold<int>(0, (sum, point) => sum + point.actualWatts);
    return sum / _dataPoints.length;
  }

  /// Gets the average target power across all data points.
  ///
  /// Returns null if history is empty.
  double? get averageTargetPower {
    if (_dataPoints.isEmpty) return null;
    final sum = _dataPoints.fold<int>(0, (sum, point) => sum + point.targetWatts);
    return sum / _dataPoints.length;
  }

  @override
  String toString() {
    return 'PowerHistory(${_dataPoints.length} points, interval: ${intervalMs}ms)';
  }
}
