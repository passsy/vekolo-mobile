import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/domain/models/workout/workout_models.dart';
import 'package:vekolo/domain/models/workout_session.dart';
import 'package:vekolo/widgets/workout_resume_dialog.dart';

void main() {
  group('WorkoutResumeDialog', () {
    late WorkoutSession testSession;

    setUp(() {
      testSession = WorkoutSession(
        id: 'test-session-123',
        workoutName: 'Sweet Spot Intervals',
        workoutPlan: WorkoutPlan(plan: [PowerBlock(id: 'b1', duration: 60000, power: 0.8)]),
        startTime: DateTime.now().subtract(Duration(minutes: 30)),
        status: SessionStatus.active,
        elapsedMs: 123000, // 2:03
        currentBlockIndex: 2,
        lastSampleTime: DateTime.now().subtract(Duration(minutes: 5)),
      );
    });

    testWidgets('shows workout information', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutResumeDialog(session: testSession),
          ),
        ),
      );

      expect(find.text('Resume Workout?'), findsOneWidget);
      expect(find.text('We found an incomplete workout session from earlier.'), findsOneWidget);

      // Check elapsed time display (2:03)
      expect(find.textContaining('2:03'), findsOneWidget);

      // Check started time
      expect(find.textContaining('Started'), findsOneWidget);
    });

    testWidgets('has three action buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutResumeDialog(session: testSession),
          ),
        ),
      );

      expect(find.text('Start Fresh'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('returns ResumeChoice.resume when Resume button tapped', (tester) async {
      ResumeChoice? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ResumeChoice>(
                    context: context,
                    builder: (ctx) => WorkoutResumeDialog(session: testSession),
                  );
                },
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Resume button
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(result, ResumeChoice.resume);
    });

    testWidgets('returns ResumeChoice.discard when Discard button tapped', (tester) async {
      ResumeChoice? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ResumeChoice>(
                    context: context,
                    builder: (ctx) => WorkoutResumeDialog(session: testSession),
                  );
                },
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Discard button
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(result, ResumeChoice.discard);
    });

    testWidgets('returns ResumeChoice.startFresh when Start Fresh button tapped', (tester) async {
      ResumeChoice? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ResumeChoice>(
                    context: context,
                    builder: (ctx) => WorkoutResumeDialog(session: testSession),
                  );
                },
                child: Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Start Fresh button
      await tester.tap(find.text('Start Fresh'));
      await tester.pumpAndSettle();

      expect(result, ResumeChoice.startFresh);
    });

    testWidgets('formats elapsed time correctly', (tester) async {
      final session = WorkoutSession(
        id: 'test',
        workoutName: 'Test',
        workoutPlan: WorkoutPlan(plan: []),
        startTime: DateTime.now(),
        status: SessionStatus.active,
        elapsedMs: 65000, // 1:05
        currentBlockIndex: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutResumeDialog(session: session),
          ),
        ),
      );

      expect(find.textContaining('1:05'), findsOneWidget);
    });

    testWidgets('formats timestamp as "Just now" for recent sessions', (tester) async {
      final session = WorkoutSession(
        id: 'test',
        workoutName: 'Test',
        workoutPlan: WorkoutPlan(plan: []),
        startTime: DateTime.now().subtract(Duration(seconds: 30)),
        status: SessionStatus.active,
        elapsedMs: 10000,
        currentBlockIndex: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutResumeDialog(session: session),
          ),
        ),
      );

      expect(find.textContaining('Just now'), findsOneWidget);
    });
  });
}
