// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library;

import 'dart:async';
import 'dart:ui' as ui;

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
  RobotTestWidgetsFlutterBinding()
    : super() {
    // Parent constructor already initializes platformDispatcher
  }

  @override
  TestRestorationManager get restorationManager {
    _restorationManager ??= createRestorationManager();
    return _restorationManager!;
  }

  TestRestorationManager? _restorationManager;

  /// Called by the test framework at the beginning of a widget test to
  /// prepare the binding for the next test.
  ///
  /// If [registerTestTextInput] returns true when this method is called,
  /// the [testTextInput] is configured to simulate the keyboard.
  @override
  void reset() {
    _restorationManager?.dispose();
    _restorationManager = null;
    platformDispatcher.defaultRouteNameTestValue = '/';
    resetGestureBinding();
    testTextInput.reset();
    if (registerTestTextInput) {
      testTextInput.register();
    }
    CustomSemanticsAction.resetForTests(); // ignore: invalid_use_of_visible_for_testing_member
    _enableFocusManagerLifecycleAwarenessIfSupported();
  }

  void _enableFocusManagerLifecycleAwarenessIfSupported() {
    if (buildOwner == null) {
      return;
    }
    buildOwner!.focusManager
        .listenToApplicationLifecycleChangesIfSupported(); // ignore: invalid_use_of_visible_for_testing_member
  }

  @override
  TestRestorationManager createRestorationManager() {
    return TestRestorationManager();
  }

  /// The value to set [debugDisableShadows] to while tests are running.
  ///
  /// This can be used to reduce the likelihood of golden file tests being
  /// flaky, because shadow rendering is not always deterministic. The
  /// [AutomatedTestWidgetsFlutterBinding] sets this to true, so that all tests
  /// always run with shadows disabled.
  @override
  @protected
  bool get disableShadows => true;

  /// Determines whether the Dart [HttpClient] class should be overridden to
  /// always return a failure response.
  ///
  /// By default, this value is true, so that unit tests will not become flaky
  /// due to intermittent network errors. The value may be overridden by a
  /// binding intended for use in integration tests that do end to end
  /// application testing, including working with real network responses.
  @override
  @protected
  bool get overrideHttpClient => true;

  /// Determines whether the binding automatically registers [testTextInput] as
  /// a fake keyboard implementation.
  ///
  /// Unit tests make use of this to mock out text input communication for
  /// widgets. An integration test would set this to false, to test real IME
  /// or keyboard input.
  ///
  /// [TestTextInput.isRegistered] reports whether the text input mock is
  /// registered or not.
  ///
  /// Some of the properties and methods on [testTextInput] are only valid if
  /// [registerTestTextInput] returns true when a test starts. If those
  /// members are accessed when using a binding that sets this flag to false,
  /// they will throw.
  ///
  /// If this property returns true when a test ends, the [testTextInput] is
  /// unregistered.
  ///
  /// This property should not change the value it returns during the lifetime
  /// of the binding. Changing the value of this property risks very confusing
  /// behavior as the [TestTextInput] may be inconsistently registered or
  /// unregistered.
  @override
  @protected
  bool get registerTestTextInput => true;

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

  @override
  void initInstances() {
    // Let parent initialize window, platformDispatcher, etc.
    super.initInstances();
    // Set our instance
    _instance = this;
    // Parent already calls binding.setupHttpOverrides() if needed
    // Parent already initializes _testTextInput
    binding.mockFlutterAssets();
  }

  @override
  // ignore: must_call_super
  void initLicenses() {
    // Do not include any licenses, because we're a test, and the LICENSE file
    // doesn't get generated for tests.
  }

  /// Artificially calls dispatchLocalesChanged on the Widget binding,
  /// then flushes microtasks.
  ///
  /// Passes only one single Locale. Use [setLocales] to pass a full preferred
  /// locales list.
  @override
  Future<void> setLocale(String languageCode, String countryCode) {
    return TestAsyncUtils.guard<void>(() async {
      assert(inTest);
      final Locale locale = Locale(languageCode, countryCode == '' ? null : countryCode);
      dispatchLocalesChanged(<Locale>[locale]);
    });
  }

  /// Artificially calls dispatchLocalesChanged on the Widget binding,
  /// then flushes microtasks.
  @override
  Future<void> setLocales(List<Locale> locales) {
    return TestAsyncUtils.guard<void>(() async {
      assert(inTest);
      dispatchLocalesChanged(locales);
    });
  }

  @override
  Future<ui.AppExitResponse> exitApplication(ui.AppExitType exitType, [int exitCode = 0]) async {
    switch (exitType) {
      case ui.AppExitType.cancelable:
        // The test framework shouldn't actually exit when requested.
        return ui.AppExitResponse.cancel;
      case ui.AppExitType.required:
        throw FlutterError('Unexpected application exit request while running test');
    }
  }

  /// Re-attempts the initialization of the lifecycle state after providing
  /// test values in [TestPlatformDispatcher.initialLifecycleStateTestValue].
  @override
  void readTestInitialLifecycleStateFromNativeWindow() {
    readInitialLifecycleStateFromNativeWindow();
  }

  Size? _surfaceSize;

  /// Artificially changes the logical size of [WidgetTester.view] to the
  /// specified size, then flushes microtasks.
  ///
  /// Set to null to use the default surface size.
  ///
  /// To avoid affecting other tests by leaking state, a test that
  /// uses this method should always reset the surface size to the default.
  /// For example, using `addTearDown`:
  /// ```dart
  ///   await binding.setSurfaceSize(someSize);
  ///   addTearDown(() => binding.setSurfaceSize(null));
  /// ```
  ///
  /// This method only affects the size of the [WidgetTester.view]. It does not
  /// affect the size of any other views. Instead of this method, consider
  /// setting [TestFlutterView.physicalSize], which works for any view,
  /// including [WidgetTester.view].
  // TODO(pdblasi-google): Deprecate this. https://github.com/flutter/flutter/issues/123881
  @override
  Future<void> setSurfaceSize(Size? size) {
    return TestAsyncUtils.guard<void>(() async {
      assert(inTest);
      if (_surfaceSize == size) {
        return;
      }
      _surfaceSize = size;
      handleMetricsChanged();
    });
  }

  @override
  void addRenderView(RenderView view) {
    _insideAddRenderView = true;
    try {
      super.addRenderView(view);
    } finally {
      _insideAddRenderView = false;
    }
  }

  bool _insideAddRenderView = false;

  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    if (_insideAddRenderView &&
        renderView.hasConfiguration &&
        renderView.configuration is TestViewConfiguration &&
        renderView == this.renderView) {
      // If a test has reached out to the now deprecated renderView property to set a custom TestViewConfiguration
      // we are not replacing it. This is to maintain backwards compatibility with how things worked prior to the
      // deprecation of that property.
      // TODO(goderbauer): Remove this "if" when the deprecated renderView property is removed.
      return renderView.configuration;
    }
    final FlutterView view = renderView.flutterView;
    if (_surfaceSize != null && view == platformDispatcher.implicitView) {
      final BoxConstraints constraints = BoxConstraints.tight(_surfaceSize!);
      return ViewConfiguration(
        logicalConstraints: constraints,
        physicalConstraints: constraints * view.devicePixelRatio,
        devicePixelRatio: view.devicePixelRatio,
      );
    }
    return super.createViewConfigurationFor(renderView);
  }

  @override
  bool debugCheckZone(String entryPoint) {
    // We skip all the zone checks in tests because the test framework makes heavy use
    // of zones and so the zones never quite match the way the framework expects.
    return true;
  }

  /// Convert the given point from the global coordinate space of the provided
  /// [RenderView] to its local one.
  ///
  /// This method operates in logical pixels for both coordinate spaces. It does
  /// not apply the device pixel ratio (used to translate to/from physical
  /// pixels).
  ///
  /// For definitions for coordinate spaces, see [TestWidgetsFlutterBinding].
  @override
  Offset globalToLocal(Offset point, RenderView view) => point;

  /// Convert the given point from the local coordinate space to the global
  /// coordinate space of the [RenderView].
  ///
  /// This method operates in logical pixels for both coordinate spaces. It does
  /// not apply the device pixel ratio to translate to physical pixels.
  ///
  /// For definitions for coordinate spaces, see [TestWidgetsFlutterBinding].
  @override
  Offset localToGlobal(Offset point, RenderView view) => point;

  /// The source of the current pointer event.
  ///
  /// The [pointerEventSource] is set as the `source` parameter of
  /// [handlePointerEventForSource] and can be used in the immediate enclosing
  /// [dispatchEvent].
  ///
  /// When [handlePointerEvent] is called directly, [pointerEventSource]
  /// is [TestBindingEventSource.device].
  ///
  /// This means that pointer events triggered by the [WidgetController] (e.g.
  /// via [WidgetController.tap]) will result in actual interactions with the
  /// UI, but other pointer events such as those from physical taps will be
  /// dropped. See also [shouldPropagateDevicePointerEvents] if this is
  /// undesired.
  @override
  TestBindingEventSource get pointerEventSource => _pointerEventSource;
  TestBindingEventSource _pointerEventSource = TestBindingEventSource.device;

  /// Whether pointer events from [TestBindingEventSource.device] will be
  /// propagated to the framework, or dropped.
  ///
  /// Setting this can be useful to interact with the app in some other way
  /// besides through the [WidgetController], such as with `adb shell input tap`
  /// on Android.
  ///
  /// See also [pointerEventSource].
  @override
  bool shouldPropagateDevicePointerEvents = false;

  /// Dispatch an event to the targets found by a hit test on its position,
  /// and remember its source as [pointerEventSource].
  ///
  /// This method sets [pointerEventSource] to `source`, forwards the call to
  /// [handlePointerEvent], then resets [pointerEventSource] to the previous
  /// value.
  ///
  /// If `source` is [TestBindingEventSource.device], then the `event` is based
  /// in the global coordinate space (for definitions for coordinate spaces,
  /// see [TestWidgetsFlutterBinding]) and the event is likely triggered by the
  /// user physically interacting with the screen during a live test on a real
  /// device (see [LiveTestWidgetsFlutterBinding]).
  ///
  /// If `source` is [TestBindingEventSource.test], then the `event` is based
  /// in the local coordinate space and the event is likely triggered by
  /// programmatically simulated pointer events, such as:
  ///
  ///  * [WidgetController.tap] and alike methods, as well as directly using
  ///    [TestGesture]. They are usually used in
  ///    [AutomatedTestWidgetsFlutterBinding] but sometimes in live tests too.
  ///  * [WidgetController.timedDrag] and alike methods. They are usually used
  ///    in macrobenchmarks.
  @override
  void handlePointerEventForSource(
    PointerEvent event, {
    TestBindingEventSource source = TestBindingEventSource.device,
  }) {
    withPointerEventSource(source, () => handlePointerEvent(event));
  }

  /// Sets [pointerEventSource] to `source`, runs `task`, then resets `source`
  /// to the previous value.
  @override
  @protected
  void withPointerEventSource(TestBindingEventSource source, VoidCallback task) {
    final TestBindingEventSource previousSource = _pointerEventSource;
    _pointerEventSource = source;
    try {
      task();
    } finally {
      _pointerEventSource = previousSource;
    }
  }

  // testTextInput is already defined in parent TestWidgetsFlutterBinding
  // No need to override it here

  /// The [State] of the current [EditableText] client of the onscreen keyboard.
  ///
  /// Setting this property to a new value causes the given [EditableTextState]
  /// to focus itself and request the keyboard to establish a
  /// [TextInputConnection].
  ///
  /// Callers must pump an additional frame after setting this property to
  /// complete the focus change.
  ///
  /// Instead of setting this directly, consider using
  /// [WidgetTester.showKeyboard].
  //
  // TODO(ianh): We should just remove this property and move the call to
  // requestKeyboard to the WidgetTester.showKeyboard method.
  @override
  EditableTextState? get focusedEditable => _focusedEditable;
  EditableTextState? _focusedEditable;
  @override
  set focusedEditable(EditableTextState? value) {
    if (_focusedEditable != value) {
      _focusedEditable = value;
      value?.requestKeyboard();
    }
  }

  void _resetFocusedEditable() {
    _focusedEditable = null;
  }

  /// Returns the exception most recently caught by the Flutter framework.
  ///
  /// Call this if you expect an exception during a test. If an exception is
  /// thrown and this is not called, then the exception is rethrown when
  /// the [testWidgets] call completes.
  ///
  /// If two exceptions are thrown in a row without the first one being
  /// acknowledged with a call to this method, then when the second exception is
  /// thrown, they are both dumped to the console and then the second is
  /// rethrown from the exception handler. This will likely result in the
  /// framework entering a highly unstable state and everything collapsing.
  ///
  /// It's safe to call this when there's no pending exception; it will return
  /// null in that case.
  @override
  dynamic takeException() {
    assert(inTest);
    final dynamic result = _pendingExceptionDetails?.exception;
    _pendingExceptionDetails = null;
    return result;
  }

  FlutterExceptionHandler? _oldExceptionHandler;
  late StackTraceDemangler _oldStackTraceDemangler;
  FlutterErrorDetails? _pendingExceptionDetails;

  _MockMessageHandler? _announcementHandler;
  List<CapturedAccessibilityAnnouncement> _announcements = <CapturedAccessibilityAnnouncement>[];

  /// {@template flutter.flutter_test.TakeAccessibilityAnnouncements}
  /// Returns a list of all the accessibility announcements made by the Flutter
  /// framework since the last time this function was called.
  ///
  /// It's safe to call this when there hasn't been any announcements; it will return
  /// an empty list in that case.
  /// {@endtemplate}
  @override
  List<CapturedAccessibilityAnnouncement> takeAnnouncements() {
    assert(inTest);
    final List<CapturedAccessibilityAnnouncement> announcements = _announcements;
    _announcements = <CapturedAccessibilityAnnouncement>[];
    return announcements;
  }

  static const TextStyle _messageStyle = TextStyle(color: Color(0xFF917FFF), fontSize: 40.0);

  static const Widget _preTestMessage = Center(
    child: Text('Test starting...', style: _messageStyle, textDirection: TextDirection.ltr),
  );

  static const Widget _postTestMessage = Center(
    child: Text('Test finished.', style: _messageStyle, textDirection: TextDirection.ltr),
  );

  /// Whether to include the output of debugDumpApp() when reporting
  /// test failures.
  @override
  bool showAppDumpInErrors = false;

  MyFakeAsync? _currentFakeAsync; // set in runTest; cleared in postTest
  Completer<void>? _pendingAsyncTasks;

  @override
  Clock get clock {
    assert(inTest);
    return _clock!;
  }

  Clock? _clock;

  @override
  DebugPrintCallback get debugPrintOverride => debugPrintSynchronously;

  /// The value of [defaultTestTimeout] can be set to `None` to enable debugging
  /// flutter tests where we would not want to timeout the test. This is
  /// expected to be used by test tooling which can detect debug mode.
  @override
  test_package.Timeout defaultTestTimeout = const test_package.Timeout(Duration(minutes: 10));

  @override
  bool get inTest => _currentFakeAsync != null;

  @override
  int get microtaskCount => _currentFakeAsync!.microtaskCount;

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
        _currentFakeAsync!.flushMicrotasks();
        handleBeginFrame(Duration(microseconds: _clock!.now().microsecondsSinceEpoch));
        _currentFakeAsync!.flushMicrotasks();
        handleDrawFrame();
      }
      _currentFakeAsync!.flushMicrotasks();
      return Future<void>.value();
    });
  }

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

  @override
  void ensureFrameCallbacksRegistered() {
    // Leave PlatformDispatcher alone, do nothing.
    assert(platformDispatcher.onDrawFrame == null);
    assert(platformDispatcher.onBeginFrame == null);
  }

  @override
  void scheduleWarmUpFrame() {
    // We override the default version of this so that the application-startup warm-up frame
    // does not schedule timers which we might never get around to running.
    assert(inTest);
    handleBeginFrame(null);
    _currentFakeAsync!.flushMicrotasks();
    handleDrawFrame();
    _currentFakeAsync!.flushMicrotasks();
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

  @override
  void scheduleAttachRootWidget(Widget rootWidget) {
    // We override the default version of this so that the application-startup widget tree
    // build does not schedule timers which we might never get around to running.
    assert(inTest);
    attachRootWidget(rootWidget);
    _currentFakeAsync!.flushMicrotasks();
  }

  @override
  Future<void> idle() {
    assert(inTest);
    final Future<void> result = idle();
    _currentFakeAsync!.elapse(Duration.zero);
    return result;
  }

  int _firstFrameDeferredCount = 0;
  bool _firstFrameSent = false;

  @override
  bool get sendFramesToEngine => _firstFrameSent || _firstFrameDeferredCount == 0;

  @override
  void deferFirstFrame() {
    assert(_firstFrameDeferredCount >= 0);
    _firstFrameDeferredCount += 1;
  }

  @override
  void allowFirstFrame() {
    assert(_firstFrameDeferredCount > 0);
    _firstFrameDeferredCount -= 1;
    // Unlike in RendererBinding.allowFirstFrame we do not force a frame here
    // to give the test full control over frame scheduling.
  }

  @override
  void resetFirstFrameSent() {
    _firstFrameSent = false;
  }

  EnginePhase _phase = EnginePhase.sendSemanticsUpdate;

  // Cloned from RendererBinding.drawFrame() but with early-exit semantics.
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
      fakeAsync.flushMicrotasks();
      while (_pendingAsyncTasks != null) {
        await _pendingAsyncTasks!.future;
        fakeAsync.flushMicrotasks();
      }
      return resultFuture;
    });
  }

  @override
  void asyncBarrier() {
    assert(_currentFakeAsync != null);
    _currentFakeAsync!.flushMicrotasks();
    TestAsyncUtils.verifyAllScopesClosed();
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

    // Disabling the warning because @visibleForTesting doesn't take the testing
    // framework itself into account, but we don't want it visible outside of
    // tests.
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
