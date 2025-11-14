import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/models/power_history.dart';

void main() {
  group('PowerDataPoint', () {
    test('creates data point with required fields', () {
      const point = PowerDataPoint(
        timestamp: 1000,
        actualWatts: 200,
        targetWatts: 180,
      );

      expect(point.timestamp, 1000);
      expect(point.actualWatts, 200);
      expect(point.targetWatts, 180);
    });

    test('equality works correctly', () {
      const point1 = PowerDataPoint(timestamp: 1000, actualWatts: 200, targetWatts: 180);
      const point2 = PowerDataPoint(timestamp: 1000, actualWatts: 200, targetWatts: 180);
      const point3 = PowerDataPoint(timestamp: 1000, actualWatts: 201, targetWatts: 180);

      expect(point1, equals(point2));
      expect(point1, isNot(equals(point3)));
    });

    test('toString includes all values', () {
      const point = PowerDataPoint(timestamp: 1000, actualWatts: 200, targetWatts: 180);
      final str = point.toString();

      expect(str, contains('1000'));
      expect(str, contains('200'));
      expect(str, contains('180'));
    });
  });

  group('PowerHistory', () {
    test('creates empty history with default settings', () {
      final history = PowerHistory();

      expect(history.isEmpty, true);
      expect(history.isNotEmpty, false);
      expect(history.length, 0);
      expect(history.dataPoints, isEmpty);
      expect(history.latest, isNull);
      expect(history.intervalMs, 15000); // Default 15s
      expect(history.maxDataPoints, 120); // Default 120 points
    });

    test('creates history with custom settings', () {
      final history = PowerHistory(intervalMs: 5000, maxDataPoints: 50);

      expect(history.intervalMs, 5000);
      expect(history.maxDataPoints, 50);
    });

    test('records first data point immediately', () {
      final history = PowerHistory();
      final recorded = history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);

      expect(recorded, true);
      expect(history.length, 1);
      expect(history.isEmpty, false);
      expect(history.isNotEmpty, true);
      expect(history.latest!.timestamp, 0);
      expect(history.latest!.actualWatts, 200);
      expect(history.latest!.targetWatts, 180);
    });

    test('skips recording if interval not elapsed', () {
      final history = PowerHistory();

      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);
      final recorded = history.record(timestamp: 5000, actualWatts: 210, targetWatts: 190);

      expect(recorded, false); // Too soon
      expect(history.length, 1); // Still only first point
    });

    test('records new data point after interval elapsed', () {
      final history = PowerHistory();

      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);
      final recorded = history.record(timestamp: 15000, actualWatts: 210, targetWatts: 190);

      expect(recorded, true);
      expect(history.length, 2);
      expect(history.latest!.timestamp, 15000);
    });

    test('enforces max data points limit', () {
      final history = PowerHistory(intervalMs: 1000, maxDataPoints: 3);

      // Add 5 points
      for (var i = 0; i < 5; i++) {
        history.record(timestamp: i * 1000, actualWatts: 200 + i, targetWatts: 180 + i);
      }

      expect(history.length, 3); // Only keeps last 3

      // First 2 should be removed
      final points = history.dataPoints;
      expect(points[0].timestamp, 2000); // Third point
      expect(points[1].timestamp, 3000); // Fourth point
      expect(points[2].timestamp, 4000); // Fifth point
    });

    test('getRange returns points in time range', () {
      final history = PowerHistory(intervalMs: 1000);

      // Add points at 0s, 1s, 2s, 3s, 4s
      for (var i = 0; i < 5; i++) {
        history.record(timestamp: i * 1000, actualWatts: 200, targetWatts: 180);
      }

      final range = history.getRange(startMs: 1000, endMs: 4000);

      expect(range.length, 3); // Points at 1s, 2s, 3s
      expect(range[0].timestamp, 1000);
      expect(range[1].timestamp, 2000);
      expect(range[2].timestamp, 3000);
    });

    test('getRange with no matches returns empty list', () {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);

      final range = history.getRange(startMs: 5000, endMs: 10000);

      expect(range, isEmpty);
    });

    test('getLastN returns last N points', () {
      final history = PowerHistory(intervalMs: 1000);

      for (var i = 0; i < 5; i++) {
        history.record(timestamp: i * 1000, actualWatts: 200 + i, targetWatts: 180);
      }

      final lastTwo = history.getLastN(2);

      expect(lastTwo.length, 2);
      expect(lastTwo[0].actualWatts, 203); // Fourth point
      expect(lastTwo[1].actualWatts, 204); // Fifth point
    });

    test('getLastN with N > length returns all points', () {
      final history = PowerHistory(intervalMs: 1000);

      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);
      history.record(timestamp: 1000, actualWatts: 210, targetWatts: 190);

      final lastTen = history.getLastN(10);

      expect(lastTen.length, 2); // Only 2 points available
    });

    test('clear removes all data points', () {
      final history = PowerHistory(intervalMs: 1000);

      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);
      history.record(timestamp: 1000, actualWatts: 210, targetWatts: 190);
      expect(history.length, 2);

      history.clear();

      expect(history.isEmpty, true);
      expect(history.length, 0);
      expect(history.latest, isNull);

      // Can record again immediately after clear
      final recorded = history.record(timestamp: 2000, actualWatts: 220, targetWatts: 200);
      expect(recorded, true);
    });

    test('averageActualPower calculates correctly', () {
      final history = PowerHistory(intervalMs: 1000);

      history.record(timestamp: 0, actualWatts: 100, targetWatts: 100);
      history.record(timestamp: 1000, actualWatts: 200, targetWatts: 200);
      history.record(timestamp: 2000, actualWatts: 300, targetWatts: 300);

      expect(history.averageActualPower, 200.0); // (100 + 200 + 300) / 3
    });

    test('averageTargetPower calculates correctly', () {
      final history = PowerHistory(intervalMs: 1000);

      history.record(timestamp: 0, actualWatts: 100, targetWatts: 120);
      history.record(timestamp: 1000, actualWatts: 200, targetWatts: 220);
      history.record(timestamp: 2000, actualWatts: 300, targetWatts: 320);

      expect(history.averageTargetPower, 220.0); // (120 + 220 + 320) / 3
    });

    test('average power returns null for empty history', () {
      final history = PowerHistory();

      expect(history.averageActualPower, isNull);
      expect(history.averageTargetPower, isNull);
    });

    test('toString includes data point count and interval', () {
      final history = PowerHistory(intervalMs: 5000);
      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);
      history.record(timestamp: 5000, actualWatts: 210, targetWatts: 190);

      final str = history.toString();

      expect(str, contains('2')); // 2 points
      expect(str, contains('5000')); // interval
    });

    test('records realistic 15-second workout data', () {
      final history = PowerHistory();

      // Simulate 5 minutes of workout (20 data points at 15s intervals)
      for (var i = 0; i < 20; i++) {
        final recorded = history.record(
          timestamp: i * 15000,
          actualWatts: 180 + (i % 5) * 10, // Varying power 180-220W
          targetWatts: 200,
        );
        expect(recorded, true);
      }

      expect(history.length, 20);
      expect(history.latest!.timestamp, 19 * 15000); // 285 seconds
    });

    test('handles zero power values', () {
      final history = PowerHistory(intervalMs: 1000);

      history.record(timestamp: 0, actualWatts: 0, targetWatts: 0);
      history.record(timestamp: 1000, actualWatts: 0, targetWatts: 100);

      expect(history.length, 2);
      expect(history.averageActualPower, 0.0);
      expect(history.averageTargetPower, 50.0);
    });

    test('handles high power values', () {
      final history = PowerHistory(intervalMs: 1000);

      history.record(timestamp: 0, actualWatts: 1500, targetWatts: 1400);

      expect(history.latest!.actualWatts, 1500);
      expect(history.latest!.targetWatts, 1400);
    });
  });
}
