import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:context_plus/context_plus.dart';

void main() {
  testWidgets('dispose is called when ContextRef.root is removed', (tester) async {
    final ref = Ref<DisposableService>();
    bool disposeCalled = false;
    DisposableService? service;

    // Build widget tree with ContextRef.root
    await tester.pumpWidget(
      ContextRef.root(
        child: Builder(
          builder: (context) {
            // Bind the ref with a dispose callback
            service = ref.bind(
              context,
              () => DisposableService(),
              dispose: (s) {
                disposeCalled = true;
                s.dispose();
              },
            );
            return const SizedBox();
          },
        ),
      ),
    );

    // Verify the service was created
    expect(service, isNotNull);
    expect(disposeCalled, isFalse);
    expect(service!.isDisposed, isFalse);

    // Remove ContextRef.root by replacing with a different widget
    // This should trigger element unmounting which calls dispose
    await tester.pumpWidget(const SizedBox());

    // Wait for all frames to settle (disposal happens during element unmount)
    await tester.pumpAndSettle();

    // Verify dispose was called
    // Note: Disposal happens when ElementDataHolder disposes _RefElementData
    // during element unmount, which should be synchronous but may need frame settling
    expect(disposeCalled, isTrue, reason: 'dispose callback should be called when ContextRef.root is removed');
    expect(service!.isDisposed, isTrue);
  });
}

class DisposableService {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    _disposed = true;
  }
}
