import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/models/power_history.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/widgets/workout_power_chart.dart';
import 'package:vekolo/widgets/workout_screen_content.dart';

void main() {
  group('WorkoutScreenContent', () {
    late PowerHistory powerHistory;
    late PowerBlock currentBlock;
    late PowerBlock nextBlock;

    setUp(() {
      powerHistory = PowerHistory();
      currentBlock = const PowerBlock(
        id: 'block1',
        duration: 300000,
        power: 0.85,
        description: 'Warm up',
      );
      nextBlock = const PowerBlock(
        id: 'block2',
        duration: 180000,
        power: 1.10,
        description: 'Work',
      );
    });

    Widget buildWidget({
      dynamic currentBlockOverride,
      dynamic nextBlockOverride,
      bool isPaused = false,
      bool isComplete = false,
      bool hasStarted = true,
      int elapsedTime = 60000,
      int remainingTime = 240000,
      int currentBlockRemainingTime = 240000,
      int powerTarget = 180,
      int? currentPower = 175,
      int? cadenceTarget = 90,
      int? currentCadence = 88,
      int? currentHeartRate = 145,
      int ftp = 200,
      double powerScaleFactor = 1.0,
      VoidCallback? onPlayPause,
      VoidCallback? onSkip,
      VoidCallback? onEndWorkout,
      VoidCallback? onPowerScaleIncrease,
      VoidCallback? onPowerScaleDecrease,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: WorkoutScreenContent(
            powerHistory: powerHistory,
            currentBlock: currentBlockOverride ?? currentBlock,
            nextBlock: nextBlockOverride ?? nextBlock,
            elapsedTime: elapsedTime,
            remainingTime: remainingTime,
            currentBlockRemainingTime: currentBlockRemainingTime,
            powerTarget: powerTarget,
            currentPower: currentPower,
            cadenceTarget: cadenceTarget,
            currentCadence: currentCadence,
            currentHeartRate: currentHeartRate,
            isPaused: isPaused,
            isComplete: isComplete,
            hasStarted: hasStarted,
            ftp: ftp,
            powerScaleFactor: powerScaleFactor,
            onPlayPause: onPlayPause ?? () {},
            onSkip: onSkip ?? () {},
            onEndWorkout: onEndWorkout ?? () {},
            onPowerScaleIncrease: onPowerScaleIncrease ?? () {},
            onPowerScaleDecrease: onPowerScaleDecrease ?? () {},
          ),
        ),
      );
    }

    testWidgets('displays timer header with elapsed and remaining time', (tester) async {
      await tester.pumpWidget(buildWidget(
        elapsedTime: 120000, // 2:00
        remainingTime: 180000, // 3:00
      ));

      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
      expect(find.text('REMAINING'), findsOneWidget);
      expect(find.text('03:00'), findsOneWidget);
    });

    testWidgets('displays power chart', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.byType(WorkoutPowerChart), findsOneWidget);
    });

    testWidgets('displays metrics cards for power, cadence, and heart rate', (tester) async {
      await tester.pumpWidget(buildWidget(
        currentPower: 180,
        powerTarget: 200,
        currentCadence: 90,
        cadenceTarget: 95,
        currentHeartRate: 150,
      ));

      expect(find.text('POWER'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
      expect(find.text('Target: 200'), findsOneWidget);

      expect(find.text('CADENCE'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('Target: 95'), findsOneWidget);

      expect(find.text('HR'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
    });

    testWidgets('displays current block information', (tester) async {
      await tester.pumpWidget(buildWidget(
        currentBlockRemainingTime: 120000, // 2:00
      ));

      expect(find.text('WARM UP'), findsOneWidget);
      expect(find.text('85% FTP'), findsOneWidget);
      expect(find.text('TIME LEFT'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('displays next block information', (tester) async {
      await tester.pumpWidget(buildWidget());

      expect(find.text('NEXT: WORK'), findsOneWidget);
      expect(find.text('110% FTP'), findsOneWidget);
    });

    testWidgets('does not display next block when null', (tester) async {
      await tester.pumpWidget(buildWidget(nextBlockOverride: null));

      expect(find.text('NEXT: WORK'), findsNothing);
    });

    testWidgets('displays ramp block correctly', (tester) async {
      final rampBlock = const RampBlock(
        id: 'ramp1',
        duration: 300000,
        powerStart: 0.5,
        powerEnd: 0.8,
        description: 'Build',
      );

      await tester.pumpWidget(buildWidget(currentBlockOverride: rampBlock));

      expect(find.text('BUILD'), findsOneWidget);
      expect(find.text('50% → 80% FTP'), findsOneWidget);
    });

    testWidgets('shows paused message when workout is paused and not started', (tester) async {
      await tester.pumpWidget(buildWidget(
        isPaused: true,
        hasStarted: false,
      ));

      expect(find.text('Start pedaling to begin workout'), findsOneWidget);
      expect(find.byIcon(Icons.pedal_bike), findsOneWidget);
    });

    testWidgets('shows paused message when workout is paused and started', (tester) async {
      await tester.pumpWidget(buildWidget(
        isPaused: true,
        hasStarted: true,
      ));

      expect(find.text('Paused - Start pedaling to resume'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle), findsOneWidget);
    });

    testWidgets('shows resume button when paused', (tester) async {
      await tester.pumpWidget(buildWidget(isPaused: true));

      expect(find.text('Resume'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('shows pause button when running', (tester) async {
      await tester.pumpWidget(buildWidget(isPaused: false));

      expect(find.text('Pause'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('calls onPlayPause when play/pause button pressed', (tester) async {
      var called = false;

      await tester.pumpWidget(buildWidget(
        isPaused: true,
        onPlayPause: () => called = true,
      ));

      await tester.tap(find.text('Resume'));
      await tester.pump();

      expect(called, true);
    });

    testWidgets('calls onSkip when skip button pressed', (tester) async {
      var called = false;

      await tester.pumpWidget(buildWidget(
        onSkip: () => called = true,
      ));

      await tester.tap(find.byIcon(Icons.skip_next));
      await tester.pump();

      expect(called, true);
    });

    testWidgets('calls onEndWorkout when end button pressed', (tester) async {
      var called = false;

      await tester.pumpWidget(buildWidget(
        onEndWorkout: () => called = true,
      ));

      await tester.tap(find.text('End Workout'));
      await tester.pump();

      expect(called, true);
    });

    testWidgets('calls onPowerScaleIncrease when + button pressed', (tester) async {
      var called = false;

      await tester.pumpWidget(buildWidget(
        onPowerScaleIncrease: () => called = true,
      ));

      // Find the + icon button (should be the add_circle_outline icon)
      final buttons = find.byIcon(Icons.add_circle_outline);
      await tester.tap(buttons.first);
      await tester.pump();

      expect(called, true);
    });

    testWidgets('calls onPowerScaleDecrease when - button pressed', (tester) async {
      var called = false;

      await tester.pumpWidget(buildWidget(
        onPowerScaleDecrease: () => called = true,
      ));

      // Find the - icon button (should be the remove_circle_outline icon)
      final buttons = find.byIcon(Icons.remove_circle_outline);
      await tester.tap(buttons.first);
      await tester.pump();

      expect(called, true);
    });

    testWidgets('displays intensity percentage', (tester) async {
      await tester.pumpWidget(buildWidget(powerScaleFactor: 1.05));

      expect(find.text('Intensity: 105%'), findsOneWidget);
    });

    testWidgets('shows workout complete card when complete', (tester) async {
      await tester.pumpWidget(buildWidget(isComplete: true));

      expect(find.text('Workout Complete!'), findsOneWidget);
      expect(find.text('Great job! You finished the workout.'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('does not show next block when workout is complete', (tester) async {
      await tester.pumpWidget(buildWidget(isComplete: true));

      expect(find.text('NEXT: WORK'), findsNothing);
    });

    testWidgets('shows complete button when workout is finished', (tester) async {
      await tester.pumpWidget(buildWidget(isComplete: true));

      expect(find.text('Complete'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('does not show intensity controls when complete', (tester) async {
      await tester.pumpWidget(buildWidget(isComplete: true));

      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    });

    testWidgets('does not show skip button when complete', (tester) async {
      await tester.pumpWidget(buildWidget(isComplete: true));

      expect(find.byIcon(Icons.skip_next), findsNothing);
    });

    testWidgets('does not show end workout button when complete', (tester) async {
      await tester.pumpWidget(buildWidget(isComplete: true));

      expect(find.text('End Workout'), findsNothing);
    });

    testWidgets('handles null current power', (tester) async {
      await tester.pumpWidget(buildWidget(currentPower: null));

      expect(find.text('--'), findsAtLeastNWidgets(1));
    });

    testWidgets('handles null cadence', (tester) async {
      await tester.pumpWidget(buildWidget(
        currentCadence: null,
        cadenceTarget: null,
      ));

      // Should still render without errors
      expect(find.byType(WorkoutScreenContent), findsOneWidget);
    });

    testWidgets('handles null heart rate', (tester) async {
      await tester.pumpWidget(buildWidget(currentHeartRate: null));

      // Heart rate should show --
      final metricCards = find.byType(Card);
      expect(metricCards, findsWidgets);
    });

    testWidgets('displays all UI elements in running state', (tester) async {
      await tester.pumpWidget(buildWidget(
        isPaused: false,
        isComplete: false,
      ));

      // Timer
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('REMAINING'), findsOneWidget);

      // Chart
      expect(find.byType(WorkoutPowerChart), findsOneWidget);

      // Metrics
      expect(find.text('POWER'), findsOneWidget);
      expect(find.text('CADENCE'), findsOneWidget);
      expect(find.text('HR'), findsOneWidget);

      // Current block
      expect(find.text('WARM UP'), findsOneWidget);

      // Next block
      expect(find.text('NEXT: WORK'), findsOneWidget);

      // Controls
      expect(find.text('Pause'), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
      expect(find.text('End Workout'), findsOneWidget);

      // Intensity controls
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.text('Intensity: 100%'), findsOneWidget);
    });
  });
}
