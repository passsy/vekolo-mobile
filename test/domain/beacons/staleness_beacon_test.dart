import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/domain/beacons/staleness_beacon.dart';

void main() {
  group('StalenessBeacon', () {
    test('forwards data immediately when emitted', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(seconds: 5));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit data
        source.value = 42;

        // Should be forwarded immediately
        BeaconScheduler.flush();
        expect(beacon.value, 42);
      });
    });

    test('emits null after staleness threshold', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit data
        source.value = 42;
        BeaconScheduler.flush();
        expect(beacon.value, 42);

        // Elapse time to trigger staleness
        async.elapse(const Duration(milliseconds: 101));
        expect(beacon.value, isNull);
      });
    });

    test('resets timer when new data arrives', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit first value
        source.value = 10;
        BeaconScheduler.flush();
        expect(beacon.value, 10);

        // Elapse 80ms (not enough to go stale)
        async.elapse(const Duration(milliseconds: 80));

        // Emit second value - this should reset the timer
        source.value = 20;
        BeaconScheduler.flush();
        expect(beacon.value, 20);

        // Elapse another 80ms (total 160ms from first, but only 80ms from second)
        async.elapse(const Duration(milliseconds: 80));

        // Should still be valid because timer was reset
        expect(beacon.value, 20);

        // Elapse enough to trigger staleness from second emission
        async.elapse(const Duration(milliseconds: 50));
        expect(beacon.value, isNull);
      });
    });

    test('does not start timer when null is emitted', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit null
        source.value = null;
        BeaconScheduler.flush();
        expect(beacon.value, isNull);

        // Elapse past threshold
        async.elapse(const Duration(milliseconds: 150));

        // Should still be null (no timer to expire)
        expect(beacon.value, isNull);
      });
    });

    test('cancels timer on dispose', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));

        // Emit data
        source.value = 42;
        BeaconScheduler.flush();
        expect(beacon.value, 42);

        // Dispose immediately
        beacon.dispose();
        source.dispose();

        // Elapse past threshold
        async.elapse(const Duration(milliseconds: 150));

        // Should still have the value (timer was cancelled)
        expect(beacon.value, 42);
      });
    });

    test('stops forwarding data after dispose', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(seconds: 5));

        // Emit initial data
        source.value = 10;
        BeaconScheduler.flush();
        expect(beacon.value, 10);

        // Dispose
        beacon.dispose();

        // Emit new data
        source.value = 20;
        BeaconScheduler.flush();

        // Should not have been forwarded
        expect(beacon.value, 10);

        source.dispose();
      });
    });

    test('handles multiple null emissions', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit null multiple times
        source.value = null;
        BeaconScheduler.flush();
        source.value = null;
        BeaconScheduler.flush();
        source.value = null;
        BeaconScheduler.flush();

        expect(beacon.value, isNull);
      });
    });

    test('handles rapid data updates', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit rapid updates
        for (int i = 0; i < 10; i++) {
          source.value = i;
          BeaconScheduler.flush();
        }

        // Last value should be present
        expect(beacon.value, 9);

        // Elapse time to trigger staleness
        async.elapse(const Duration(milliseconds: 120));
        expect(beacon.value, isNull);
      });
    });

    test('can be disposed multiple times safely', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(seconds: 5));

        beacon.dispose();
        beacon.dispose(); // Should not throw
        beacon.dispose(); // Should not throw

        source.dispose();
      });
    });

    test('works with extension method', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = source.withStalenessDetection(threshold: const Duration(milliseconds: 100));
        addTearDown(() {
          beacon.dispose();
          source.dispose();
        });

        // Emit data
        source.value = 42;
        BeaconScheduler.flush();
        expect(beacon.value, 42);

        // Elapse time to trigger staleness
        async.elapse(const Duration(milliseconds: 101));
        expect(beacon.value, isNull);
      });
    });

    test('can be used in derived beacon for dependency tracking', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));

        // Create a derived beacon that depends on staleness beacon
        final derived = Beacon.derived(() {
          final val = beacon.value;
          return val != null ? val * 2 : 0;
        });
        addTearDown(() {
          derived.dispose();
          beacon.dispose();
          source.dispose();
        });

        // Emit data
        source.value = 21;
        BeaconScheduler.flush();
        expect(derived.value, 42);

        // Elapse time to trigger staleness
        async.elapse(const Duration(milliseconds: 101));
        expect(derived.value, 0); // Should recompute when beacon becomes null
      });
    });

    test('notifies observers when value changes', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));

        int notificationCount = 0;
        final unsubscribe = beacon.subscribe((_) {
          notificationCount++;
        });
        addTearDown(() {
          unsubscribe();
          beacon.dispose();
          source.dispose();
        });

        // Initial emission
        source.value = 42;
        BeaconScheduler.flush();
        expect(notificationCount, 1);

        // Staleness timeout
        async.elapse(const Duration(milliseconds: 101));
        BeaconScheduler.flush();
        expect(notificationCount, 2);

        // Another value
        source.value = 100;
        BeaconScheduler.flush();
        expect(notificationCount, 3);
      });
    });

    test('does not notify observers when value does not change', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);
        final beacon = StalenessBeacon(source, const Duration(milliseconds: 100));

        int notificationCount = 0;
        final unsubscribe = beacon.subscribe((_) {
          notificationCount++;
        });
        addTearDown(() {
          unsubscribe();
          beacon.dispose();
          source.dispose();
        });
        BeaconScheduler.flush();
        expect(notificationCount, 1); // initial

        source.value = null;
        BeaconScheduler.flush();
        expect(notificationCount, 1); // unchanged

        // Emit a value
        source.value = 42;
        BeaconScheduler.flush();
        expect(notificationCount, 2);

        // Emit same value again
        source.value = 42;
        BeaconScheduler.flush();
        expect(notificationCount, 2); // Should not notify
      });
    });

    test('can be chained with other beacon transforms', () {
      fakeAsync((async) {
        final source = Beacon.writable<int?>(null);

        // Create a chain: source -> staleness -> map
        final staleAware = source.withStalenessDetection(threshold: const Duration(milliseconds: 100));
        final mapped = staleAware.map((value) => value != null ? value * 2 : -1);
        addTearDown(() {
          mapped.dispose();
          staleAware.dispose();
          source.dispose();
        });

        // Emit data
        source.value = 21;
        BeaconScheduler.flush();
        expect(mapped.value, 42);

        // Elapse time to trigger staleness
        async.elapse(const Duration(milliseconds: 101));
        expect(mapped.value, -1); // null mapped to -1
      });
    });
  });
}
