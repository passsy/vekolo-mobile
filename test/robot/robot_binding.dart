// ignore_for_file: deprecated_member_use, overridden_fields
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_trace/stack_trace.dart' as stack_trace;
import 'package:test_api/scaffolding.dart' as test_package show Timeout;

import 'package:flutter_test/src/_binding_io.dart'
    if (dart.library.js_interop) 'package:flutter_test/src/_binding_web.dart'
    as binding;

import 'my_fake_async.dart';

/// A variant of [TestWidgetsFlutterBinding] that uses [MyFakeAsync]
/// instead of the standard FakeAsync for custom time control.
///
/// This is a complete alternative to AutomatedTestWidgetsFlutterBinding.
class RobotTestWidgetsFlutterBinding extends TestWidgetsFlutterBinding {
  RobotTestWidgetsFlutterBinding() : super() {
    // Parent constructor already initializes platformDispatcher
  }

  /// The value to set [debugDisableShadows] to while tests are running.
  ///
  /// This can be used to reduce the likelihood of golden file tests being
  /// flaky, because shadow rendering is not always deterministic. The
  /// [AutomatedTestWidgetsFlutterBinding] sets this to true, so that all tests
  /// always run with shadows disabled.
  // Override: Changes default from false to true for deterministic golden tests
  @override
  @protected
  bool get disableShadows => true;

  /// The current [RobotTestWidgetsFlutterBinding], if one has been created.
  ///
  /// The binding must be initialized before using this getter. If you
  /// need the binding to be constructed before calling [testWidgets],
  /// you can ensure a binding has been constructed by calling the
  /// [TestWidgetsFlutterBinding.ensureInitialized] function.
  static RobotTestWidgetsFlutterBinding get instance => BindingBase.checkInstance(_instance);
  static RobotTestWidgetsFlutterBinding? _instance;

  /// Returns an instance of the binding that implements
  /// [TestWidgetsFlutterBinding]. If no binding has yet been initialized, the
  /// [RobotTestWidgetsFlutterBinding] class is instantiated, and becomes the
  /// binding.
  static RobotTestWidgetsFlutterBinding ensureInitialized() {
    if (RobotTestWidgetsFlutterBinding._instance == null) {
      RobotTestWidgetsFlutterBinding();
    }
    return RobotTestWidgetsFlutterBinding.instance;
  }

  // Override: Must set _instance for our custom singleton
  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    binding.mockFlutterAssets();
  }

  MyFakeAsync? _currentFakeAsync; // set in runTest; cleared in postTest
  Completer<void>? _pendingAsyncTasks;

  // Private fields for exception handling and announcements - used by _runTest and postTest
  FlutterExceptionHandler? _oldExceptionHandler;
  late StackTraceDemangler _oldStackTraceDemangler;
  FlutterErrorDetails? _pendingExceptionDetails;
  _MockMessageHandler? _announcementHandler;
  List<CapturedAccessibilityAnnouncement> _announcements = <CapturedAccessibilityAnnouncement>[];

  static const TextStyle _messageStyle = TextStyle(color: Color(0xFF917FFF), fontSize: 40.0);
  static const Widget _preTestMessage = Center(
    child: Text('Test starting...', style: _messageStyle, textDirection: TextDirection.ltr),
  );
  static const Widget _postTestMessage = Center(
    child: Text('Test finished.', style: _messageStyle, textDirection: TextDirection.ltr),
  );

  // Override: Returns MyFakeAsync's clock instead of real clock
  @override
  Clock get clock {
    assert(inTest);
    return _clock!;
  }

  Clock? _clock;

  // Override: Uses synchronous debug print for automated tests
  @override
  DebugPrintCallback get debugPrintOverride => debugPrintSynchronously;

  // Override: Sets 10-minute timeout for automated tests
  @override
  test_package.Timeout defaultTestTimeout = const test_package.Timeout(Duration(minutes: 10));

  // Override: Returns true when MyFakeAsync is active
  @override
  bool get inTest => _currentFakeAsync != null;

  // Override: Delegates to MyFakeAsync's microtask counter
  /// Always 0, because the MyFakeAsync implementation executes microtasks right away
  @override
  int get microtaskCount => 0;

  // Override: Uses MyFakeAsync to control time advancement
  @override
  Future<void> pump([Duration? duration, EnginePhase newPhase = EnginePhase.sendSemanticsUpdate]) {
    return TestAsyncUtils.guard<void>(() {
      assert(inTest);
      assert(_clock != null);
      if (duration != null) {
        _currentFakeAsync!.elapse(duration);
      }
      _phase = newPhase;
      if (hasScheduledFrame) {
        handleBeginFrame(Duration(microseconds: _clock!.now().microsecondsSinceEpoch));
        handleDrawFrame();
      }
      return Future<void>.value();
    });
  }

  // Override: Integrates real async operations with MyFakeAsync's microtask flushing
  @override
  Future<T?> runAsync<T>(Future<T> Function() callback) {
    assert(() {
      if (_pendingAsyncTasks == null) {
        return true;
      }
      fail(
        'Reentrant call to runAsync() denied.\n'
        'runAsync() was called, then before its future completed, it '
        'was called again. You must wait for the first returned future '
        'to complete before calling runAsync() again.',
      );
    }());

    final Zone realAsyncZone = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask: (Zone self, ZoneDelegate parent, Zone zone, void Function() f) {
          _rootDelegate.scheduleMicrotask(zone, f);
        },
        createTimer: (Zone self, ZoneDelegate parent, Zone zone, Duration duration, void Function() f) {
          return _rootDelegate.createTimer(zone, duration, f);
        },
        createPeriodicTimer:
            (Zone self, ZoneDelegate parent, Zone zone, Duration period, void Function(Timer timer) f) {
              return _rootDelegate.createPeriodicTimer(zone, period, f);
            },
      ),
    );

    return realAsyncZone.run<Future<T?>>(() {
      final Completer<T?> result = Completer<T?>();
      _pendingAsyncTasks = Completer<void>();
      try {
        callback().then(result.complete).catchError((Object exception, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: exception,
              stack: stack,
              library: 'Flutter test framework',
              context: ErrorDescription('while running async test code'),
              informationCollector: () {
                return <DiagnosticsNode>[ErrorHint('The exception was caught asynchronously.')];
              },
            ),
          );
          result.complete(null);
        });
      } catch (exception, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: 'Flutter test framework',
            context: ErrorDescription('while running async test code'),
            informationCollector: () {
              return <DiagnosticsNode>[ErrorHint('The exception was caught synchronously.')];
            },
          ),
        );
        result.complete(null);
      }
      result.future.whenComplete(() {
        _pendingAsyncTasks!.complete();
        _pendingAsyncTasks = null;
      });
      return result.future;
    });
  }

  // Override: Prevents automatic frame scheduling by platform
  @override
  void ensureFrameCallbacksRegistered() {
    // Leave PlatformDispatcher alone, do nothing.
    assert(platformDispatcher.onDrawFrame == null);
    assert(platformDispatcher.onBeginFrame == null);
  }

  // Override: Uses MyFakeAsync for microtask flushing during warm-up
  @override
  void scheduleWarmUpFrame() {
    assert(inTest);
    handleBeginFrame(null);
    handleDrawFrame();
  }

  /// The [ZoneDelegate] for [Zone.root].
  ///
  /// Used to schedule (real) microtasks and timers in the root zone,
  /// to be run in the correct zone.
  static final ZoneDelegate _rootDelegate = _captureRootZoneDelegate();

  /// Hack to extract the [ZoneDelegate] for [Zone.root].
  static ZoneDelegate _captureRootZoneDelegate() {
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

  // Override: Uses MyFakeAsync for microtask flushing when attaching root widget
  @override
  void scheduleAttachRootWidget(Widget rootWidget) {
    assert(inTest);
    attachRootWidget(rootWidget);
  }

  // Override: Advances MyFakeAsync clock during idle
  @override
  Future<void> idle() {
    assert(inTest);
    final Future<void> result = super.idle();
    _currentFakeAsync!.elapse(Duration.zero);
    return result;
  }

  int _firstFrameDeferredCount = 0;
  bool _firstFrameSent = false;

  // Override: Custom first-frame tracking for test control
  @override
  bool get sendFramesToEngine => _firstFrameSent || _firstFrameDeferredCount == 0;

  // Override: Custom first-frame deferral counting
  @override
  void deferFirstFrame() {
    assert(_firstFrameDeferredCount >= 0);
    _firstFrameDeferredCount += 1;
  }

  // Override: Custom first-frame deferral counting
  @override
  void allowFirstFrame() {
    assert(_firstFrameDeferredCount > 0);
    _firstFrameDeferredCount -= 1;
    // Unlike in RendererBinding.allowFirstFrame we do not force a frame here
    // to give the test full control over frame scheduling.
  }

  // Override: Resets custom first-frame tracking
  @override
  void resetFirstFrameSent() {
    _firstFrameSent = false;
  }

  EnginePhase _phase = EnginePhase.sendSemanticsUpdate;

  // Override: Custom drawFrame with early-exit by phase for test control
  @override
  void drawFrame() {
    assert(inTest);
    try {
      debugBuildingDirtyElements = true;
      buildOwner!.buildScope(rootElement!);
      if (_phase != EnginePhase.build) {
        rootPipelineOwner.flushLayout();
        if (_phase != EnginePhase.layout) {
          rootPipelineOwner.flushCompositingBits();
          if (_phase != EnginePhase.compositingBits) {
            rootPipelineOwner.flushPaint();
            if (_phase != EnginePhase.paint && sendFramesToEngine) {
              _firstFrameSent = true;
              for (final RenderView renderView in renderViews) {
                renderView.compositeFrame(); // this sends the bits to the GPU
              }
              if (_phase != EnginePhase.composite) {
                rootPipelineOwner.flushSemantics(); // this sends the semantics to the OS.
                assert(_phase == EnginePhase.flushSemantics || _phase == EnginePhase.sendSemanticsUpdate);
              }
            }
          }
        }
      }
      buildOwner!.finalizeTree();
    } finally {
      debugBuildingDirtyElements = false;
    }
  }

  // Override: Advances MyFakeAsync clock instead of real delay
  @override
  Future<void> delayed(Duration duration) {
    assert(_currentFakeAsync != null);
    _currentFakeAsync!.elapse(duration);
    return Future<void>.value();
  }

  /// Simulates the synchronous passage of time, resulting from blocking or
  /// expensive calls.
  void elapseBlocking(Duration duration) {
    _currentFakeAsync!.elapseBlocking(duration);
  }

  // Override: Wraps test in MyFakeAsync zone instead of standard FakeAsync
  @override
  Future<void> runTest(Future<void> Function() testBody, VoidCallback invariantTester, {String description = ''}) {
    assert(!inTest);
    assert(_currentFakeAsync == null);
    assert(_clock == null);

    final MyFakeAsync fakeAsync = MyFakeAsync();
    _currentFakeAsync = fakeAsync; // reset in postTest
    _clock = fakeAsync.getClock(DateTime.utc(2015));
    late Future<void> testBodyResult;
    fakeAsync.run((MyFakeAsync localFakeAsync) {
      assert(fakeAsync == _currentFakeAsync);
      assert(fakeAsync == localFakeAsync);
      testBodyResult = _runTest(testBody, invariantTester, description);
      assert(inTest);
    });

    return Future<void>.microtask(() async {
      // testBodyResult is a Future that was created in the Zone of the
      // fakeAsync. This means that if we await it here, it will register a
      // microtask to handle the future _in the fake async zone_. We avoid this
      // by calling '.then' in the current zone. While flushing the microtasks
      // of the fake-zone below, the new future will be completed and can then
      // be used without fakeAsync.

      final Future<void> resultFuture = testBodyResult.then<void>((_) {
        // Do nothing.
      });

      // Resolve interplay between fake async and real async calls.
      while (_pendingAsyncTasks != null) {
        await _pendingAsyncTasks!.future;
      }
      return resultFuture;
    });
  }

  // Override: Flushes MyFakeAsync microtasks before checking scope closure
  @override
  void asyncBarrier() {
    assert(_currentFakeAsync != null);
    super.asyncBarrier();
  }

  Zone? _parentZone;

  VoidCallback _createTestCompletionHandler(String testDescription, Completer<void> completer) {
    return () {
      // This can get called twice, in the case of a Future without listeners failing, and then
      // our main future completing.
      assert(Zone.current == _parentZone);
      if (_pendingExceptionDetails != null) {
        debugPrint = debugPrintOverride; // just in case the test overrides it -- otherwise we won't see the error!
        reportTestException(_pendingExceptionDetails!, testDescription);
        _pendingExceptionDetails = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    };
  }

  // Override: Cleans up exception handlers, focus manager, and MyFakeAsync state
  @override
  void postTest() {
    assert(inTest);
    FlutterError.onError = _oldExceptionHandler;
    FlutterError.demangleStackTrace = _oldStackTraceDemangler;
    _pendingExceptionDetails = null;
    _parentZone = null;
    buildOwner!.focusManager.dispose();

    if (TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.checkMockMessageHandler(
      SystemChannels.accessibility.name,
      _announcementHandler,
    )) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockDecodedMessageHandler(
        SystemChannels.accessibility,
        null,
      );
      _announcementHandler = null;
    }
    _announcements = <CapturedAccessibilityAnnouncement>[];

    ServicesBinding.instance.keyEventManager.keyMessageHandler = null;
    buildOwner!.focusManager = FocusManager()..registerGlobalHandlers();

    // ignore: invalid_use_of_visible_for_testing_member
    RawKeyboard.instance.clearKeysPressed();
    // ignore: invalid_use_of_visible_for_testing_member
    HardwareKeyboard.instance.clearState();
    // ignore: invalid_use_of_visible_for_testing_member
    keyEventManager.clearState();
    // ignore: invalid_use_of_visible_for_testing_member
    RendererBinding.instance.initMouseTracker();

    assert(ServicesBinding.instance == WidgetsBinding.instance);
    // ignore: invalid_use_of_visible_for_testing_member
    ServicesBinding.instance.resetInternalState();
    assert(_currentFakeAsync != null);
    assert(_clock != null);
    _clock = null;
    _currentFakeAsync = null;
  }

  Future<void> _handleAnnouncementMessage(Object? mockMessage) async {
    if (mockMessage! case {'type': 'announce', 'data': final Map<Object?, Object?> data as Map<Object?, Object?>}) {
      _announcements.add(
        _PrivateCapturedAccessibilityAnnouncement._(
          data['message'].toString(),
          TextDirection.values[data['textDirection']! as int],
          Assertiveness.values[(data['assertiveness'] ?? 0) as int],
        ),
      );
    }
  }

  Future<void> _runTest(Future<void> Function() testBody, VoidCallback invariantTester, String description) {
    assert(inTest);

    // Set the handler only if there is currently none.
    if (TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.checkMockMessageHandler(
      SystemChannels.accessibility.name,
      null,
    )) {
      _announcementHandler = _handleAnnouncementMessage;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        _announcementHandler,
      );
    }

    _oldExceptionHandler = FlutterError.onError;
    _oldStackTraceDemangler = FlutterError.demangleStackTrace;
    int exceptionCount = 0; // number of un-taken exceptions
    FlutterError.onError = (FlutterErrorDetails details) {
      if (_pendingExceptionDetails != null) {
        debugPrint = debugPrintOverride; // just in case the test overrides it -- otherwise we won't see the errors!
        if (exceptionCount == 0) {
          exceptionCount = 2;
          FlutterError.dumpErrorToConsole(_pendingExceptionDetails!, forceReport: true);
        } else {
          exceptionCount += 1;
        }
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        _pendingExceptionDetails = FlutterErrorDetails(
          exception:
              'Multiple exceptions ($exceptionCount) were detected during the running of the current test, and at least one was unexpected.',
          library: 'Flutter test framework',
        );
      } else {
        reportExceptionNoticed(details); // mostly this is just a hook for the LiveTestWidgetsFlutterBinding
        _pendingExceptionDetails = details;
      }
    };
    FlutterError.demangleStackTrace = (StackTrace stack) {
      // package:stack_trace uses ZoneSpecification.errorCallback to add useful
      // information to stack traces, meaning Trace and Chain classes can be
      // present. Because these StackTrace implementations do not follow the
      // format the framework expects, we convert them to a vm trace here.
      if (stack is stack_trace.Trace) {
        return stack.vmTrace;
      }
      if (stack is stack_trace.Chain) {
        return stack.toTrace().vmTrace;
      }
      return stack;
    };
    final Completer<void> testCompleter = Completer<void>();
    final VoidCallback testCompletionHandler = _createTestCompletionHandler(description, testCompleter);
    void handleUncaughtError(Object exception, StackTrace stack) {
      if (testCompleter.isCompleted) {
        // Well this is not a good sign.
        // Ideally, once the test has failed we would stop getting errors from the test.
        // However, if someone tries hard enough they could get in a state where this happens.
        // If we silently dropped these errors on the ground, nobody would ever know. So instead
        // we raise them and fail the test after it has already completed.
        debugPrint = debugPrintOverride; // just in case the test overrides it -- otherwise we won't see the error!
        reportTestException(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            context: ErrorDescription('running a test (but after the test had completed)'),
            library: 'Flutter test framework',
          ),
          description,
        );
        return;
      }
      // This is where test failures, e.g. those in expect(), will end up.
      // Specifically, runUnaryGuarded() will call this synchronously and
      // return our return value if _runTestBody fails synchronously (which it
      // won't, so this never happens), and Future will call this when the
      // Future completes with an error and it would otherwise call listeners
      // if the listener is in a different zone (which it would be for the
      // `whenComplete` handler below), or if the Future completes with an
      // error and the future has no listeners at all.
      //
      // This handler further calls the onError handler above, which sets
      // _pendingExceptionDetails. Nothing gets printed as a result of that
      // call unless we already had an exception pending, because in general
      // we want people to be able to cause the framework to report exceptions
      // and then use takeException to verify that they were really caught.
      // Now, if we actually get here, this isn't going to be one of those
      // cases. We only get here if the test has actually failed. So, once
      // we've carefully reported it, we then immediately end the test by
      // calling the testCompletionHandler in the _parentZone.
      //
      // We have to manually call testCompletionHandler because if the Future
      // library calls us, it is maybe _instead_ of calling a registered
      // listener from a different zone. In our case, that would be instead of
      // calling the whenComplete() listener below.
      //
      // We have to call it in the parent zone because if we called it in
      // _this_ zone, the test framework would find this zone was the current
      // zone and helpfully throw the error in this zone, causing us to be
      // directly called again.
      DiagnosticsNode treeDump;
      try {
        treeDump = rootElement?.toDiagnosticsNode() ?? DiagnosticsNode.message('<no tree>');
        // We try to stringify the tree dump here (though we immediately discard the result) because
        // we want to make sure that if it can't be serialized, we replace it with a message that
        // says the tree could not be serialized. Otherwise, the real exception might get obscured
        // by side-effects of the underlying issues causing the tree dumping code to flail.
        treeDump.toStringDeep();
      } catch (exception) {
        treeDump = DiagnosticsNode.message(
          '<additional error caught while dumping tree: $exception>',
          level: DiagnosticLevel.error,
        );
      }
      final List<DiagnosticsNode> omittedFrames = <DiagnosticsNode>[];
      final int stackLinesToOmit = reportExpectCall(stack, omittedFrames);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          context: ErrorDescription('running a test'),
          library: 'Flutter test framework',
          stackFilter: (Iterable<String> frames) {
            return FlutterError.defaultStackFilter(frames.skip(stackLinesToOmit));
          },
          informationCollector: () sync* {
            if (stackLinesToOmit > 0) {
              yield* omittedFrames;
            }
            if (showAppDumpInErrors) {
              yield DiagnosticsProperty<DiagnosticsNode>(
                'At the time of the failure, the widget tree looked as follows',
                treeDump,
                linePrefix: '# ',
                style: DiagnosticsTreeStyle.flat,
              );
            }
            if (description.isNotEmpty) {
              yield DiagnosticsProperty<String>(
                'The test description was',
                description,
                style: DiagnosticsTreeStyle.errorProperty,
              );
            }
          },
        ),
      );
      assert(_parentZone != null);
      assert(
        _pendingExceptionDetails != null,
        'A test overrode FlutterError.onError but either failed to return it to its original state, or had unexpected additional errors that it could not handle. Typically, this is caused by using expect() before restoring FlutterError.onError.',
      );
      _parentZone!.run<void>(testCompletionHandler);
    }

    final ZoneSpecification errorHandlingZoneSpecification = ZoneSpecification(
      handleUncaughtError: (Zone self, ZoneDelegate parent, Zone zone, Object exception, StackTrace stack) {
        handleUncaughtError(exception, stack);
      },
    );
    _parentZone = Zone.current;
    final Zone testZone = _parentZone!.fork(specification: errorHandlingZoneSpecification);
    testZone
        .runBinary<Future<void>, Future<void> Function(), VoidCallback>(_runTestBody, testBody, invariantTester)
        .whenComplete(testCompletionHandler);
    return testCompleter.future;
  }

  Future<void> _runTestBody(Future<void> Function() testBody, VoidCallback invariantTester) async {
    assert(inTest);
    // So that we can assert that it remains the same after the test finishes.
    _beforeTestCheckIntrinsicSizes = debugCheckIntrinsicSizes;

    runApp(Container(key: UniqueKey(), child: _preTestMessage)); // Reset the tree to a known state.
    await pump();
    // Pretend that the first frame produced in the test body is the first frame
    // sent to the engine.
    resetFirstFrameSent();

    final bool autoUpdateGoldensBeforeTest = autoUpdateGoldenFiles && !isBrowser;
    final TestExceptionReporter reportTestExceptionBeforeTest = reportTestException;
    final ErrorWidgetBuilder errorWidgetBuilderBeforeTest = ErrorWidget.builder;
    final bool shouldPropagateDevicePointerEventsBeforeTest = shouldPropagateDevicePointerEvents;

    // run the test
    await testBody();
    asyncBarrier(); // drains the microtasks in `flutter test` mode (when using AutomatedTestWidgetsFlutterBinding)

    if (_pendingExceptionDetails == null) {
      // We only try to clean up and verify invariants if we didn't already
      // fail. If we got an exception already, then we instead leave everything
      // alone so that we don't cause more spurious errors.
      runApp(Container(key: UniqueKey(), child: _postTestMessage)); // Unmount any remaining widgets.
      await pump();
      if (registerTestTextInput) {
        testTextInput.unregister();
      }
      invariantTester();
      _verifyAutoUpdateGoldensUnset(autoUpdateGoldensBeforeTest && !isBrowser);
      _verifyReportTestExceptionUnset(reportTestExceptionBeforeTest);
      _verifyErrorWidgetBuilderUnset(errorWidgetBuilderBeforeTest);
      _verifyShouldPropagateDevicePointerEventsUnset(shouldPropagateDevicePointerEventsBeforeTest);
      _verifyInvariants();
    }

    assert(inTest);
    asyncBarrier(); // When using AutomatedTestWidgetsFlutterBinding, this flushes the microtasks.
  }

  late bool _beforeTestCheckIntrinsicSizes;

  void _verifyInvariants() {
    assert(debugAssertNoTransientCallbacks('An animation is still running even after the widget tree was disposed.'));
    assert(debugAssertNoPendingPerformanceModeRequests('A performance mode was requested and not disposed by a test.'));
    assert(debugAssertNoTimeDilation('The timeDilation was changed and not reset by the test.'));
    assert(
      debugAssertAllFoundationVarsUnset(
        'The value of a foundation debug variable was changed by the test.',
        debugPrintOverride: debugPrintOverride,
      ),
    );
    assert(debugAssertAllGesturesVarsUnset('The value of a gestures debug variable was changed by the test.'));
    assert(
      debugAssertAllPaintingVarsUnset(
        'The value of a painting debug variable was changed by the test.',
        debugDisableShadowsOverride: disableShadows,
      ),
    );
    assert(
      debugAssertAllRenderVarsUnset(
        'The value of a rendering debug variable was changed by the test.',
        debugCheckIntrinsicSizesOverride: _beforeTestCheckIntrinsicSizes,
      ),
    );
    assert(debugAssertAllWidgetVarsUnset('The value of a widget debug variable was changed by the test.'));
    assert(debugAssertAllSchedulerVarsUnset('The value of a scheduler debug variable was changed by the test.'));
    assert(debugAssertAllServicesVarsUnset('The value of a services debug variable was changed by the test.'));
  }

  void _verifyAutoUpdateGoldensUnset(bool valueBeforeTest) {
    assert(() {
      if (autoUpdateGoldenFiles != valueBeforeTest) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError('The value of autoUpdateGoldenFiles was changed by the test.'),
            stack: StackTrace.current,
            library: 'Flutter test framework',
          ),
        );
      }
      return true;
    }());
  }

  void _verifyReportTestExceptionUnset(TestExceptionReporter valueBeforeTest) {
    assert(() {
      if (reportTestException != valueBeforeTest) {
        // We can't report this error to their modified reporter because we
        // can't be guaranteed that their reporter will cause the test to fail.
        // So we reset the error reporter to its initial value and then report
        // this error.
        reportTestException = valueBeforeTest;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError('The value of reportTestException was changed by the test.'),
            stack: StackTrace.current,
            library: 'Flutter test framework',
          ),
        );
      }
      return true;
    }());
  }

  void _verifyErrorWidgetBuilderUnset(ErrorWidgetBuilder valueBeforeTest) {
    assert(() {
      if (ErrorWidget.builder != valueBeforeTest) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError('The value of ErrorWidget.builder was changed by the test.'),
            stack: StackTrace.current,
            library: 'Flutter test framework',
          ),
        );
      }
      return true;
    }());
  }

  void _verifyShouldPropagateDevicePointerEventsUnset(bool valueBeforeTest) {
    assert(() {
      if (shouldPropagateDevicePointerEvents != valueBeforeTest) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError('The value of shouldPropagateDevicePointerEvents was changed by the test.'),
            stack: StackTrace.current,
            library: 'Flutter test framework',
          ),
        );
      }
      return true;
    }());
  }

  @override
  void reportExceptionNoticed(FlutterErrorDetails exception) {
    // By default we do nothing.
    // The LiveTestWidgetsFlutterBinding overrides this to report the exception to the console.
  }
}

/// Signature of callbacks used to intercept messages on a given channel.
///
/// See [TestDefaultBinaryMessenger.setMockDecodedMessageHandler] for more details.
typedef _MockMessageHandler = Future<void> Function(Object?);

class _PrivateCapturedAccessibilityAnnouncement implements CapturedAccessibilityAnnouncement {
  const _PrivateCapturedAccessibilityAnnouncement._(this.message, this.textDirection, this.assertiveness);

  /// The accessibility message announced by the framework.
  @override
  final String message;

  /// The direction in which the text of the [message] flows.
  @override
  final TextDirection textDirection;

  /// Determines the assertiveness level of the accessibility announcement.
  @override
  final Assertiveness assertiveness;
}
