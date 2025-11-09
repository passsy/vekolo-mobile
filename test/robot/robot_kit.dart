import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/scaffolding.dart' as test_package;

import 'package:matcher/expect.dart' as matcher_expect;
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:clock/clock.dart';
import 'package:spot/spot.dart';

// ignore: depend_on_referenced_packages
import 'package:test_api/src/backend/invoker.dart';

import 'robot_binding.dart';
import 'vekolo_robot.dart';
import 'package:leak_tracker/leak_tracker.dart';
import 'package:leak_tracker_testing/leak_tracker_testing.dart';

/// If leak tracking is enabled, stops it and
/// declares notDisposed objects as leaks.
void maybeTearDownLeakTrackingForTest() {
  if (!LeakTesting.enabled || !LeakTracking.isStarted || LeakTracking.phase.ignoreLeaks) {
    return;
  }
  LeakTracking.phase = const PhaseSettings.ignored();
}

@isTest
void robotTest(
  String description,
  Future<void> Function(VekoloRobot robot) callback, {
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  dynamic tags,
  bool useRobotBinding = true,
}) {
  final List<dynamic Function()> flutterTearDowns = [() => _lastTestStartTime = null];

  if (useRobotBinding) {
    final binding = RobotTestWidgetsFlutterBinding.ensureInitialized();
    final MyWidgetTester tester = MyWidgetTester._(binding);
    test(
      description,
      () async {
        await runZoned(() async {
          tester._testDescription = description;
          SemanticsHandle? semanticsHandle;
          tester._recordNumberOfSemanticsHandles();
          if (semanticsEnabled) {
            semanticsHandle = tester.ensureSemantics();
          }
          test_package.addTearDown(binding.postTest);
          return binding.runTest(
            () async {
              debugResetSemanticsIdCounter();
              try {
                binding.reset(); // TODO(ianh): the binding should just do this itself in _runTest

                final robot = VekoloRobot(tester: tester);
                await callback(robot);

                runApp(Container(key: UniqueKey()));
                await tester.pump();
              } catch (e, stack) {
                // In case of an error, Flutter does not cleanup the widget tree.
                // (see: TestWidgetsFlutterBinding._runTestBody)
                // This is required, so that all widget dispose methods are called, and all subscriptions to plugins are canceled.
                // Only then channel.setMockMethodCallHandler can be set to null. without causing all following test to fail

                // Unmount any remaining widgets.
                runApp(Container(key: UniqueKey(), child: _postTestErrorMessage(e)));
                await tester.pump();
                rethrow;
              } finally {
                await Invoker.current!.runTearDowns(flutterTearDowns);
                flutterTearDowns.clear();
              }
              semanticsHandle?.dispose();
            },
            tester._endOfTestVerifications,
            description: description,
          );
        }, zoneValues: {#flutter_test.teardowns: flutterTearDowns});
      },
      skip: skip,
      timeout: timeout ?? binding.defaultTestTimeout,
      tags: tags,
    );
  }

  testWidgets(
    description,
    (tester) async {
      return runZoned(() async {
        try {
          final robot = VekoloRobot(tester: tester);
          await callback(robot);

          runApp(Container(key: UniqueKey()));
          await tester.pump();
          // await Future.delayed(Duration(milliseconds: 100));
        } catch (e) {
          // In case of an error, Flutter does not cleanup the widget tree.
          // (see: TestWidgetsFlutterBinding._runTestBody)
          // This is required, so that all widget dispose methods are called, and all subscriptions to plugins are canceled.
          // Only then channel.setMockMethodCallHandler can be set to null. without causing all following test to fail

          // Unmount any remaining widgets.
          runApp(Container(key: UniqueKey(), child: _postTestErrorMessage(e)));
          await tester.pump();
          rethrow;
        } finally {
          await Invoker.current!.runTearDowns(flutterTearDowns);
          flutterTearDowns.clear();
        }
      }, zoneValues: {#flutter_test.teardowns: flutterTearDowns});
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    tags: tags,
  );
}

/// Class that programmatically interacts with widgets and the test environment.
///
/// Typically, a test uses [pumpWidget] to load a widget tree (in a manner very
/// similar to how [runApp] works in a Flutter application). Then, methods such
/// as [tap], [drag], [enterText], [fling], [longPress], etc, can be used to
/// interact with the application. The application runs in a [FakeAsync] zone,
/// which allows time to be stepped forward deliberately; this is done using the
/// [pump] method.
///
/// The [expect] function can then be used to examine the state of the
/// application, typically using [Finder]s such as those in the [find]
/// namespace, and [Matcher]s such as [findsOneWidget].
///
/// ```dart
/// testWidgets('MyWidget', (WidgetTester tester) async {
///   await tester.pumpWidget(const MyWidget());
///   await tester.tap(find.text('Save'));
///   await tester.pump(); // allow the application to handle
///   await tester.pump(const Duration(seconds: 1)); // skip past the animation
///   expect(find.text('Success'), findsOneWidget);
/// });
/// ```
///
/// For convenience, instances of this class (such as the one provided by
/// `testWidgets`) can be used as the `vsync` for `AnimationController` objects.
///
/// When the binding is [LiveTestWidgetsFlutterBinding], events from
/// [LiveTestWidgetsFlutterBinding.deviceEventDispatcher] will be handled in
/// [dispatchEvent]. Thus, using `flutter run` to run a test lets one tap on
/// the screen to generate [Finder]s relevant to the test.
/// A custom widget tester that is API-compatible with [WidgetTester].
///
/// This class cannot extend [WidgetTester] directly because WidgetTester's
/// constructor is private to the flutter_test package. However, it implements
/// the exact same API surface, making it a drop-in replacement.
///
/// This provides full backwards compatibility - anywhere you would use a
/// [WidgetTester], you can use [MyWidgetTester] instead.
class MyWidgetTester extends WidgetController implements HitTestDispatcher, TickerProvider, WidgetTester {
  MyWidgetTester._(super.binding);

  /// The description string of the test currently being run.
  String get testDescription => _testDescription;
  String _testDescription = '';

  /// The binding instance used by the testing framework.
  @override
  TestWidgetsFlutterBinding get binding => super.binding as TestWidgetsFlutterBinding;

  /// Renders the UI from the given [widget].
  ///
  /// Calls [runApp] with the given widget, then triggers a frame and flushes
  /// microtasks, by calling [pump] with the same `duration` (if any). The
  /// supplied [EnginePhase] is the final phase reached during the pump pass; if
  /// not supplied, the whole pass is executed.
  ///
  /// Subsequent calls to this is different from [pump] in that it forces a full
  /// rebuild of the tree, even if [widget] is the same as the previous call.
  /// [pump] will only rebuild the widgets that have changed.
  ///
  /// This method should not be used as the first parameter to an [expect] or
  /// [expectLater] call to test that a widget throws an exception. Instead, use
  /// [TestWidgetsFlutterBinding.takeException].
  ///
  /// {@tool snippet}
  /// ```dart
  /// testWidgets('MyWidget asserts invalid bounds', (WidgetTester tester) async {
  ///   await tester.pumpWidget(const MyWidget());
  ///   expect(tester.takeException(), isAssertionError); // or isNull, as appropriate.
  /// });
  /// ```
  /// {@end-tool}
  ///
  /// By default, the provided `widget` is rendered into [WidgetTester.view],
  /// whose properties tests can modify to simulate different scenarios (e.g.
  /// running on a large/small screen). Tests that want to control the
  /// [FlutterView] into which content is rendered can set `wrapWithView` to
  /// false and use [View] widgets in the provided `widget` tree to specify the
  /// desired [FlutterView]s.
  ///
  /// See also [LiveTestWidgetsFlutterBindingFramePolicy], which affects how
  /// this method works when the test is run with `flutter run`.
  Future<void> pumpWidget(
    Widget widget, {
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
    bool wrapWithView = true,
  }) {
    return TestAsyncUtils.guard<void>(() {
      binding.attachRootWidget(wrapWithView ? binding.wrapWithDefaultView(widget) : widget);
      binding.scheduleFrame();
      return binding.pump(duration, phase);
    });
  }

  @override
  Future<List<Duration>> handlePointerEventRecord(Iterable<PointerEventRecord> records) {
    assert(records.isNotEmpty);
    return TestAsyncUtils.guard<List<Duration>>(() async {
      final List<Duration> handleTimeStampDiff = <Duration>[];
      DateTime? startTime;
      for (final PointerEventRecord record in records) {
        final DateTime now = binding.clock.now();
        startTime ??= now;
        // So that the first event is promised to receive a zero timeDiff
        final Duration timeDiff = record.timeDelay - now.difference(startTime);
        if (timeDiff.isNegative) {
          // Flush all past events
          handleTimeStampDiff.add(-timeDiff);
          for (final PointerEvent event in record.events) {
            binding.handlePointerEventForSource(event, source: TestBindingEventSource.test);
          }
        } else {
          await binding.pump();
          await binding.delayed(timeDiff);
          handleTimeStampDiff.add(binding.clock.now().difference(startTime) - record.timeDelay);
          for (final PointerEvent event in record.events) {
            binding.handlePointerEventForSource(event, source: TestBindingEventSource.test);
          }
        }
      }
      await binding.pump();
      // This makes sure that a gesture is completed, with no more pointers
      // active.
      return handleTimeStampDiff;
    });
  }

  /// Triggers a frame after `duration` amount of time.
  ///
  /// This makes the framework act as if the application had janked (missed
  /// frames) for `duration` amount of time, and then received a "Vsync" signal
  /// to paint the application.
  ///
  /// For a [FakeAsync] environment (typically in `flutter test`), this advances
  /// time and timeout counting; for a live environment this delays `duration`
  /// time.
  ///
  /// This is a convenience function that just calls
  /// [TestWidgetsFlutterBinding.pump].
  ///
  /// See also [LiveTestWidgetsFlutterBindingFramePolicy], which affects how
  /// this method works when the test is run with `flutter run`.
  @override
  Future<void> pump([Duration? duration, EnginePhase phase = EnginePhase.sendSemanticsUpdate]) {
    return TestAsyncUtils.guard<void>(() => binding.pump(duration, phase));
  }

  /// Triggers a frame after `duration` amount of time, return as soon as the frame is drawn.
  ///
  /// This enables driving an artificially high CPU load by rendering frames in
  /// a tight loop. It must be used with the frame policy set to
  /// [LiveTestWidgetsFlutterBindingFramePolicy.benchmark].
  ///
  /// Similarly to [pump], this doesn't actually wait for `duration`, just
  /// advances the clock.
  Future<void> pumpBenchmark(Duration duration) async {
    assert(() {
      final TestWidgetsFlutterBinding widgetsBinding = binding;
      return widgetsBinding is LiveTestWidgetsFlutterBinding &&
          widgetsBinding.framePolicy == LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
    }());

    dynamic caughtException;
    StackTrace? stackTrace;
    void handleError(dynamic error, StackTrace trace) {
      caughtException ??= error;
      stackTrace ??= trace;
    }

    await Future<void>.microtask(() {
      binding.handleBeginFrame(duration);
    }).catchError(handleError);
    await idle();
    await Future<void>.microtask(() {
      binding.handleDrawFrame();
    }).catchError(handleError);
    await idle();

    if (caughtException != null) {
      Error.throwWithStackTrace(caughtException as Object, stackTrace!);
    }
  }

  @override
  Future<int> pumpAndSettle([
    Duration duration = const Duration(milliseconds: 100),
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
    Duration timeout = const Duration(minutes: 10),
  ]) {
    assert(duration > Duration.zero);
    assert(timeout > Duration.zero);
    assert(() {
      final WidgetsBinding binding = this.binding;
      if (binding is LiveTestWidgetsFlutterBinding &&
          binding.framePolicy == LiveTestWidgetsFlutterBindingFramePolicy.benchmark) {
        matcher_expect.fail(
          'When using LiveTestWidgetsFlutterBindingFramePolicy.benchmark, '
          'hasScheduledFrame is never set to true. This means that pumpAndSettle() '
          'cannot be used, because it has no way to know if the application has '
          'stopped registering new frames.',
        );
      }
      return true;
    }());
    return TestAsyncUtils.guard<int>(() async {
      final DateTime endTime = binding.clock.fromNowBy(timeout);
      int count = 0;
      do {
        if (binding.clock.now().isAfter(endTime)) {
          throw FlutterError('pumpAndSettle timed out');
        }
        await binding.pump(duration, phase);
        count += 1;
      } while (binding.hasScheduledFrame);
      return count;
    });
  }

  /// Repeatedly pump frames that render the `target` widget with a fixed time
  /// `interval` as many as `maxDuration` allows.
  ///
  /// The `maxDuration` argument is required. The `interval` argument defaults to
  /// 16.683 milliseconds (59.94 FPS).
  Future<void> pumpFrames(
    Widget target,
    Duration maxDuration, [
    Duration interval = const Duration(milliseconds: 16, microseconds: 683),
  ]) {
    // The interval following the last frame doesn't have to be within the fullDuration.
    Duration elapsed = Duration.zero;
    return TestAsyncUtils.guard<void>(() async {
      binding.attachRootWidget(binding.wrapWithDefaultView(target));
      binding.scheduleFrame();
      while (elapsed < maxDuration) {
        await binding.pump(interval);
        elapsed += interval;
      }
    });
  }

  /// Simulates restoring the state of the widget tree after the application
  /// is restarted.
  ///
  /// The method grabs the current serialized restoration data from the
  /// [RestorationManager], takes down the widget tree to destroy all in-memory
  /// state, and then restores the widget tree from the serialized restoration
  /// data.
  Future<void> restartAndRestore() async {
    assert(
      binding.restorationManager.debugRootBucketAccessed,
      'The current widget tree did not inject the root bucket of the RestorationManager and '
      'therefore no restoration data has been collected to restore from. Did you forget to wrap '
      'your widget tree in a RootRestorationScope?',
    );
    return TestAsyncUtils.guard<void>(() async {
      final RootWidget widget = binding.rootElement!.widget as RootWidget;
      final TestRestorationData restorationData = binding.restorationManager.restorationData;
      runApp(Container(key: UniqueKey()));
      await pump();
      binding.restorationManager.restoreFrom(restorationData);
      binding.attachToBuildOwner(widget);
      binding.scheduleFrame();
      return binding.pump();
    });
  }

  /// Retrieves the current restoration data from the [RestorationManager].
  ///
  /// The returned [TestRestorationData] describes the current state of the
  /// widget tree under test and can be provided to [restoreFrom] to restore
  /// the widget tree to the state described by this data.
  Future<TestRestorationData> getRestorationData() async {
    assert(
      binding.restorationManager.debugRootBucketAccessed,
      'The current widget tree did not inject the root bucket of the RestorationManager and '
      'therefore no restoration data has been collected. Did you forget to wrap your widget tree '
      'in a RootRestorationScope?',
    );
    return binding.restorationManager.restorationData;
  }

  /// Restores the widget tree under test to the state described by the
  /// provided [TestRestorationData].
  ///
  /// The data provided to this method is usually obtained from
  /// [getRestorationData].
  Future<void> restoreFrom(TestRestorationData data) {
    binding.restorationManager.restoreFrom(data);
    return pump();
  }

  /// Runs a [callback] that performs real asynchronous work.
  ///
  /// This is intended for callers who need to call asynchronous methods where
  /// the methods spawn isolates or OS threads and thus cannot be executed
  /// synchronously by calling [pump].
  ///
  /// If callers were to run these types of asynchronous tasks directly in
  /// their test methods, they run the possibility of encountering deadlocks.
  ///
  /// If [callback] completes successfully, this will return the future
  /// returned by [callback].
  ///
  /// If [callback] completes with an error, the error will be caught by the
  /// Flutter framework and made available via [takeException], and this method
  /// will return a future that completes with `null`.
  ///
  /// Re-entrant calls to this method are not allowed; callers of this method
  /// are required to wait for the returned future to complete before calling
  /// this method again. Attempts to do otherwise will result in a
  /// [TestFailure] error being thrown.
  ///
  /// If your widget test hangs and you are using [runAsync], chances are your
  /// code depends on the result of a task that did not complete. Fake async
  /// environment is unable to resolve a future that was created in [runAsync].
  /// If you observe such behavior or flakiness, you have a number of options:
  ///
  /// * Consider restructuring your code so you do not need [runAsync]. This is
  ///   the optimal solution as widget tests are designed to run in fake async
  ///   environment.
  ///
  /// * Expose a [Future] in your application code that signals the readiness of
  ///   your widget tree, then await that future inside [callback].
  Future<T?> runAsync<T>(
    Future<T> Function() callback, {
    @Deprecated(
      'This is no longer supported and has no effect. '
      'This feature was deprecated after v3.12.0-1.1.pre.',
    )
    Duration additionalTime = const Duration(milliseconds: 1000),
  }) => binding.runAsync<T?>(callback);

  /// Whether there are any transient callbacks scheduled.
  ///
  /// This essentially checks whether all animations have completed.
  ///
  /// See also:
  ///
  ///  * [pumpAndSettle], which essentially calls [pump] until there are no
  ///    scheduled frames.
  ///  * [SchedulerBinding.transientCallbackCount], which is the value on which
  ///    this is based.
  ///  * [SchedulerBinding.hasScheduledFrame], which is true whenever a frame is
  ///    pending. [SchedulerBinding.hasScheduledFrame] is made true when a
  ///    widget calls [State.setState], even if there are no transient callbacks
  ///    scheduled. This is what [pumpAndSettle] uses.
  bool get hasRunningAnimations => binding.transientCallbackCount > 0;

  @override
  HitTestResult hitTestOnBinding(Offset location, {int? viewId}) {
    viewId ??= view.viewId;
    final RenderView renderView = binding.renderViews.firstWhere((RenderView r) => r.flutterView.viewId == viewId);
    location = binding.localToGlobal(location, renderView);
    return super.hitTestOnBinding(location, viewId: viewId);
  }

  @override
  Future<void> sendEventToBinding(PointerEvent event) {
    return TestAsyncUtils.guard<void>(() async {
      binding.handlePointerEventForSource(event, source: TestBindingEventSource.test);
    });
  }

  /// Handler for device events caught by the binding in live test mode.
  ///
  /// [PointerDownEvent]s received here will only print a diagnostic message
  /// showing possible [Finder]s that can be used to interact with the widget at
  /// the location of [result].
  @override
  void dispatchEvent(PointerEvent event, HitTestResult result) {
    if (event is PointerDownEvent) {
      final RenderObject innerTarget = result.path
          .map((HitTestEntry candidate) => candidate.target)
          .whereType<RenderObject>()
          .first;
      final Element? innerTargetElement = binding.renderViews.contains(innerTarget)
          ? null
          : _lastWhereOrNull(
              collectAllElementsFrom(binding.rootElement!, skipOffstage: true),
              (Element element) => element.renderObject == innerTarget,
            );
      if (innerTargetElement == null) {
        printToConsole('No widgets found at ${event.position}.');
        return;
      }
      final List<Element> candidates = <Element>[];
      innerTargetElement.visitAncestorElements((Element element) {
        candidates.add(element);
        return true;
      });
      assert(candidates.isNotEmpty);
      String? descendantText;
      int numberOfWithTexts = 0;
      int numberOfTypes = 0;
      int totalNumber = 0;
      printToConsole('Some possible finders for the widgets at ${event.position}:');
      for (final Element element in candidates) {
        if (totalNumber > 13) {
          break;
        }
        totalNumber += 1; // optimistically assume we'll be able to describe it

        final Widget widget = element.widget;
        if (widget is Tooltip) {
          final String message = widget.message ?? widget.richMessage!.toPlainText();
          final Iterable<Element> matches = find.byTooltip(message).evaluate();
          if (matches.length == 1) {
            printToConsole("  find.byTooltip('$message')");
            continue;
          }
        }

        if (widget is Text) {
          assert(descendantText == null);
          assert(widget.data != null || widget.textSpan != null);
          final String text = widget.data ?? widget.textSpan!.toPlainText();
          final Iterable<Element> matches = find.text(text).evaluate();
          descendantText = widget.data;
          if (matches.length == 1) {
            printToConsole("  find.text('$text')");
            continue;
          }
        }

        final Key? key = widget.key;
        if (key is ValueKey<dynamic>) {
          final String? keyLabel = switch (key.value) {
            int() || double() || bool() => 'const ${key.runtimeType}(${key.value})',
            final String value => "const Key('$value')",
            _ => null,
          };
          if (keyLabel != null) {
            final Iterable<Element> matches = find.byKey(key).evaluate();
            if (matches.length == 1) {
              printToConsole('  find.byKey($keyLabel)');
              continue;
            }
          }
        }

        if (!_isPrivate(widget.runtimeType)) {
          if (numberOfTypes < 5) {
            final Iterable<Element> matches = find.byType(widget.runtimeType).evaluate();
            if (matches.length == 1) {
              printToConsole('  find.byType(${widget.runtimeType})');
              numberOfTypes += 1;
              continue;
            }
          }

          if (descendantText != null && numberOfWithTexts < 5) {
            final Iterable<Element> matches = find.widgetWithText(widget.runtimeType, descendantText).evaluate();
            if (matches.length == 1) {
              printToConsole("  find.widgetWithText(${widget.runtimeType}, '$descendantText')");
              numberOfWithTexts += 1;
              continue;
            }
          }
        }

        if (!_isPrivate(element.runtimeType)) {
          final Iterable<Element> matches = find.byElementType(element.runtimeType).evaluate();
          if (matches.length == 1) {
            printToConsole('  find.byElementType(${element.runtimeType})');
            continue;
          }
        }

        totalNumber -= 1; // if we got here, we didn't actually find something to say about it
      }
      if (totalNumber == 0) {
        printToConsole('  <could not come up with any unique finders>');
      }
    }
  }

  bool _isPrivate(Type type) {
    // used above so that we don't suggest matchers for private types
    return '_'.matchAsPrefix(type.toString()) != null;
  }

  /// Returns the exception most recently caught by the Flutter framework.
  ///
  /// See [TestWidgetsFlutterBinding.takeException] for details.
  dynamic takeException() {
    return binding.takeException();
  }

  /// {@macro flutter.flutter_test.TakeAccessibilityAnnouncements}
  ///
  /// See [TestWidgetsFlutterBinding.takeAnnouncements] for details.
  List<CapturedAccessibilityAnnouncement> takeAnnouncements() {
    return binding.takeAnnouncements();
  }

  /// Acts as if the application went idle.
  ///
  /// Runs all remaining microtasks, including those scheduled as a result of
  /// running them, until there are no more microtasks scheduled. Then, runs any
  /// previously scheduled timers with zero time, and completes the returned future.
  ///
  /// May result in an infinite loop or run out of memory if microtasks continue
  /// to recursively schedule new microtasks. Will not run any timers scheduled
  /// after this method was invoked, even if they are zero-time timers.
  Future<void> idle() {
    return TestAsyncUtils.guard<void>(() => binding.idle());
  }

  Set<Ticker>? _tickers;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _tickers ??= <_TestTicker>{};
    final _TestTicker result = _TestTicker(onTick, _removeTicker);
    _tickers!.add(result);
    return result;
  }

  void _removeTicker(_TestTicker ticker) {
    assert(_tickers != null);
    assert(_tickers!.contains(ticker));
    _tickers!.remove(ticker);
  }

  /// Throws an exception if any tickers created by the [WidgetTester] are still
  /// active when the method is called.
  ///
  /// An argument can be specified to provide a string that will be used in the
  /// error message. It should be an adverbial phrase describing the current
  /// situation, such as "at the end of the test".
  void verifyTickersWereDisposed([String when = 'when none should have been']) {
    if (_tickers != null) {
      for (final Ticker ticker in _tickers!) {
        if (ticker.isActive) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('A Ticker was active $when.'),
            ErrorDescription('All Tickers must be disposed.'),
            ErrorHint(
              'Tickers used by AnimationControllers '
              'should be disposed by calling dispose() on the AnimationController itself. '
              'Otherwise, the ticker will leak.',
            ),
            ticker.describeForError('The offending ticker was'),
          ]);
        }
      }
    }
  }

  void _endOfTestVerifications() {
    verifyTickersWereDisposed('at the end of the test');
    _verifySemanticsHandlesWereDisposed();
  }

  void _verifySemanticsHandlesWereDisposed() {
    assert(_lastRecordedSemanticsHandles != null);
    // TODO(goderbauer): Fix known leak in web engine when running integration tests and remove this "correction", https://github.com/flutter/flutter/issues/121640.
    final int knownWebEngineLeakForLiveTestsCorrection = kIsWeb && binding is LiveTestWidgetsFlutterBinding ? 1 : 0;

    if (_currentSemanticsHandles - knownWebEngineLeakForLiveTestsCorrection > _lastRecordedSemanticsHandles!) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('A SemanticsHandle was active at the end of the test.'),
        ErrorDescription(
          'All SemanticsHandle instances must be disposed by calling dispose() on '
          'the SemanticsHandle.',
        ),
      ]);
    }
    _lastRecordedSemanticsHandles = null;
  }

  int? _lastRecordedSemanticsHandles;

  // TODO(goderbauer): Only use binding.debugOutstandingSemanticsHandles when deprecated binding.pipelineOwner is removed.
  int get _currentSemanticsHandles =>
      binding.debugOutstandingSemanticsHandles + binding.pipelineOwner.debugOutstandingSemanticsHandles;

  void _recordNumberOfSemanticsHandles() {
    _lastRecordedSemanticsHandles = _currentSemanticsHandles;
  }

  /// Returns the TestTextInput singleton.
  ///
  /// Typical app tests will not need to use this value. To add text to widgets
  /// like [TextField] or [TextFormField], call [enterText].
  ///
  /// Some of the properties and methods on this value are only valid if the
  /// binding's [TestWidgetsFlutterBinding.registerTestTextInput] flag is set to
  /// true as a test is starting (meaning that the keyboard is to be simulated
  /// by the test framework). If those members are accessed when using a binding
  /// that sets this flag to false, they will throw.
  TestTextInput get testTextInput => binding.testTextInput;

  /// Give the text input widget specified by [finder] the focus, as if the
  /// onscreen keyboard had appeared.
  ///
  /// Implies a call to [pump].
  ///
  /// The widget specified by [finder] must be an [EditableText] or have
  /// an [EditableText] descendant. For example `find.byType(TextField)`
  /// or `find.byType(TextFormField)`, or `find.byType(EditableText)`.
  ///
  /// Tests that just need to add text to widgets like [TextField]
  /// or [TextFormField] only need to call [enterText].
  Future<void> showKeyboard(FinderBase<Element> finder) async {
    bool skipOffstage = true;
    if (finder is Finder) {
      skipOffstage = finder.skipOffstage;
    }
    return TestAsyncUtils.guard<void>(() async {
      final EditableTextState editable = state<EditableTextState>(
        find.descendant(
          of: finder,
          matching: find.byType(EditableText, skipOffstage: skipOffstage),
          matchRoot: true,
        ),
      );
      // Setting focusedEditable causes the binding to call requestKeyboard()
      // on the EditableTextState, which itself eventually calls TextInput.attach
      // to establish the connection.
      binding.focusedEditable = editable;
      await pump();
    });
  }

  /// Give the text input widget specified by [finder] the focus and replace its
  /// content with [text], as if it had been provided by the onscreen keyboard.
  ///
  /// The widget specified by [finder] must be an [EditableText] or have
  /// an [EditableText] descendant. For example `find.byType(TextField)`
  /// or `find.byType(TextFormField)`, or `find.byType(EditableText)`.
  ///
  /// When the returned future completes, the text input widget's text will be
  /// exactly `text`, and the caret will be placed at the end of `text`.
  ///
  /// To just give [finder] the focus without entering any text,
  /// see [showKeyboard].
  ///
  /// To enter text into other widgets (e.g. a custom widget that maintains a
  /// TextInputConnection the way that a [EditableText] does), first ensure that
  /// that widget has an open connection (e.g. by using [tap] to focus it),
  /// then call `testTextInput.enterText` directly (see
  /// [TestTextInput.enterText]).
  Future<void> enterText(FinderBase<Element> finder, String text) async {
    return TestAsyncUtils.guard<void>(() async {
      await showKeyboard(finder);
      testTextInput.enterText(text);
      await idle();
    });
  }

  /// Makes an effort to dismiss the current page with a Material [Scaffold] or
  /// a [CupertinoPageScaffold].
  ///
  /// Will throw an error if there is no back button in the page.
  Future<void> pageBack() async {
    return TestAsyncUtils.guard<void>(() async {
      Finder backButton = find.byTooltip('Back');
      if (backButton.evaluate().isEmpty) {
        backButton = find.byType(CupertinoNavigationBarBackButton);
      }

      expectSync(backButton, findsOneWidget, reason: 'One back button expected on screen');

      await tap(backButton);
    });
  }

  @override
  void printToConsole(String message) {
    binding.debugPrintOverride(message);
  }
}

/// The [ZoneDelegate] for [Zone.root].
///
/// Used to schedule (real) microtasks and timers in the root zone,
/// to be run in the correct zone.
final ZoneDelegate _rootDelegate = _captureRootZoneDelegate();

/// Hack to extract the [ZoneDelegate] for [Zone.root].
ZoneDelegate _captureRootZoneDelegate() {
  final Zone captureZone = Zone.root.fork(
    specification: ZoneSpecification(
      run: <R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) {
        return parent as R;
      },
    ),
  );
  // The `_captureRootZoneDelegate` argument just happens to be a constant
  // function with the necessary type. It's not called recursively.
  return captureZone.run<ZoneDelegate>(_captureRootZoneDelegate);
}

DateTime? _lastTestStartTime;
void addRobotEvent(String message, {bool isError = false}) {
  _lastTestStartTime ??= clock.now();
  final duration = clock.now().difference(_lastTestStartTime!);

  final type = isError ? 'Robot Error' : 'Robot';
  final formatted = '$type [${duration.inSeconds}s]: $message';
  // ignore: avoid_print
  print(formatted);
  final color = isError ? const Color(0xFFA31616) : const Color(0xFF166316);
  timeline.addEvent(details: formatted, eventType: type, color: color);
  if (isError) {
    throw message;
  }
}

Widget _postTestErrorMessage(Object e) {
  return Center(
    child: Text(
      'Test errored with $e',
      style: const TextStyle(color: Color(0xFF917FFF), fontSize: 40.0),
      textDirection: TextDirection.ltr,
    ),
  );
}

/// A special version of [addTearDown] that is executed before [testWidgets] completes.
///
/// Only to be used in conjunction with [robotTest].
///
/// It is required for configurations that need to be reset before the flutter test finishes, like:
///
/// - [debugDefaultTargetPlatformOverride]
/// - [debugImageOverheadAllowance]
/// - [debugInvertOversizedImages]
/// - [debugOnPaintImage]
/// - [debugNetworkImageHttpClientProvider]
void addFlutterTearDown(dynamic Function() callback) {
  if (Invoker.current == null) {
    throw StateError('addFlutterTearDown() may only be called within a test.');
  }

  final list = Zone.current[#flutter_test.teardowns] as List?;
  if (list == null) {
    throw StateError('addFlutterTearDown() may only be called within using testWidgets2');
  }
  list.add(callback);
}

// Return the last element that satisfies `test`, or return null if not found.
E? _lastWhereOrNull<E>(Iterable<E> list, bool Function(E) test) {
  late E result;
  bool foundMatching = false;
  for (final E element in list) {
    if (test(element)) {
      result = element;
      foundMatching = true;
    }
  }
  if (foundMatching) {
    return result;
  }
  return null;
}

typedef _TickerDisposeCallback = void Function(_TestTicker ticker);

class _TestTicker extends Ticker {
  _TestTicker(super.onTick, this._onDispose);

  final _TickerDisposeCallback _onDispose;

  @override
  void dispose() {
    _onDispose(this);
    super.dispose();
  }
}
