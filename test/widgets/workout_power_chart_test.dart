import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/models/power_history.dart';
import 'package:vekolo/widgets/workout_power_chart.dart';

void main() {
  group('WorkoutPowerChart', () {
    testWidgets('shows waiting message when no data', (tester) async {
      final history = PowerHistory();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      expect(find.text('Waiting for data...'), findsOneWidget);
    });

    testWidgets('renders bars for data points', (tester) async {
      final history = PowerHistory(intervalMs: 1000);

      // Add 5 data points
      for (var i = 0; i < 5; i++) {
        history.record(timestamp: i * 1000, actualWatts: 200, targetWatts: 180);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      // Should have bars (Stack widgets for each data point)
      expect(find.byType(Stack), findsNWidgets(5));
    });

    testWidgets('limits visible bars to maxVisibleBars', (tester) async {
      final history = PowerHistory(intervalMs: 1000);

      // Add 30 data points
      for (var i = 0; i < 30; i++) {
        history.record(timestamp: i * 1000, actualWatts: 200, targetWatts: 180);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(
              powerHistory: history,
              maxVisibleBars: 10, // Only show last 10
            ),
          ),
        ),
      );

      // Should only show 10 bars
      expect(find.byType(Stack), findsNWidgets(10));
    });

    testWidgets('uses custom height', (tester) async {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(
              powerHistory: history,
              height: 200,
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.height, 200);
    });

    testWidgets('shows legend with target and actual colors', (tester) async {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      expect(find.text('Target'), findsOneWidget);
      expect(find.text('Actual'), findsOneWidget);
    });

    testWidgets('handles zero power values', (tester) async {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 0, targetWatts: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      // Should render without errors
      expect(find.byType(WorkoutPowerChart), findsOneWidget);
    });

    testWidgets('handles high power values', (tester) async {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 1500, targetWatts: 1400);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      // Should render without errors
      expect(find.byType(WorkoutPowerChart), findsOneWidget);
    });

    testWidgets('updates when new data is added', (tester) async {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      expect(find.byType(Stack), findsOneWidget);

      // Add more data
      history.record(timestamp: 1000, actualWatts: 210, targetWatts: 190);
      history.record(timestamp: 2000, actualWatts: 220, targetWatts: 200);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(powerHistory: history),
          ),
        ),
      );

      expect(find.byType(Stack), findsNWidgets(3));
    });

    testWidgets('renders with FTP for zone colors', (tester) async {
      final history = PowerHistory(intervalMs: 1000);

      // Add data points at different power zones
      history.record(timestamp: 0, actualWatts: 100, targetWatts: 100); // Recovery
      history.record(timestamp: 1000, actualWatts: 150, targetWatts: 150); // Endurance
      history.record(timestamp: 2000, actualWatts: 200, targetWatts: 200); // Threshold

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(
              powerHistory: history,
              ftp: 200,
            ),
          ),
        ),
      );

      // Should render different colored bars based on zones
      expect(find.byType(WorkoutPowerChart), findsOneWidget);
      expect(find.byType(Stack), findsNWidgets(3));
    });

    testWidgets('renders without FTP (uses default colors)', (tester) async {
      final history = PowerHistory(intervalMs: 1000);
      history.record(timestamp: 0, actualWatts: 200, targetWatts: 180);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(
              powerHistory: history,
              ftp: null, // No FTP
            ),
          ),
        ),
      );

      expect(find.byType(WorkoutPowerChart), findsOneWidget);
    });

    testWidgets('renders realistic workout scenario', (tester) async {
      final history = PowerHistory(intervalMs: 15000);

      // Simulate 2 minutes of workout (8 data points at 15s intervals)
      final powers = [150, 160, 170, 200, 210, 200, 180, 160];
      for (var i = 0; i < powers.length; i++) {
        history.record(
          timestamp: i * 15000,
          actualWatts: powers[i],
          targetWatts: 200,
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(
              powerHistory: history,
              ftp: 200,
            ),
          ),
        ),
      );

      expect(find.byType(Stack), findsNWidgets(8));
      expect(find.text('Target'), findsOneWidget);
      expect(find.text('Actual'), findsOneWidget);
    });

    testWidgets('shows only most recent bars when scrolling', (tester) async {
      final history = PowerHistory(intervalMs: 1000);

      // Add 100 data points (simulating long workout)
      for (var i = 0; i < 100; i++) {
        history.record(timestamp: i * 1000, actualWatts: 180 + i, targetWatts: 200);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutPowerChart(
              powerHistory: history,
              maxVisibleBars: 20, // Only show last 20
            ),
          ),
        ),
      );

      // Should only show 20 bars (most recent)
      expect(find.byType(Stack), findsNWidgets(20));
    });
  });
}
