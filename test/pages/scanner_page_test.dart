import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_test/flutter_test.dart';
import 'package:vekolo/ble/ble_scanner.dart';
import 'package:vekolo/config/ble_config.dart';
import 'package:vekolo/pages/scanner_page.dart';

import '../ble/fake_ble_permissions.dart';
import '../ble/fake_ble_platform.dart';

void main() {
  group('ScannerPage - Device Persistence', () {
    testWidgets('devices stay visible after pressing stop button', (tester) async {
      // Create test infrastructure
      final platform = FakeBlePlatform();
      final permissions = FakeBlePermissions();
      final scanner = BleScanner(platform: platform, permissions: permissions);
      scanner.initialize();

      // Set up ready state
      platform.setAdapterState(fbp.BluetoothAdapterState.on);
      permissions.setHasPermission(true);
      permissions.setLocationServiceEnabled(true);

      // Build the widget with context_plus providing the scanner
      await tester.pumpWidget(
        ContextRef.root(
          child: Builder(
            builder: (context) {
              bleScannerRef.bind(context, () => scanner);
              return const MaterialApp(
                home: ScannerPage(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scanner should auto-start when ready
      expect(scanner.isScanning.value, isTrue, reason: 'Scanner should auto-start when Bluetooth is ready');

      // Add some devices
      final device1 = platform.addDevice('00:11:22:33:44:55', 'Trainer 1', rssi: -50);
      final device2 = platform.addDevice('00:11:22:33:44:66', 'Trainer 2', rssi: -60);
      device1.turnOn();
      device2.turnOn();
      await tester.pumpAndSettle();

      // Verify devices are shown with RSSI
      expect(find.text('Trainer 1'), findsOneWidget);
      expect(find.text('Trainer 2'), findsOneWidget);
      expect(find.textContaining('RSSI: -50'), findsOneWidget);
      expect(find.textContaining('RSSI: -60'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));

      // Stop scanning
      final stopButton = find.text('Stop');
      expect(stopButton, findsOneWidget);
      await tester.tap(stopButton);
      await tester.pumpAndSettle();

      // CRITICAL: Devices should still be visible
      expect(find.text('Trainer 1'), findsOneWidget, reason: 'Trainer 1 should still be visible after stop');
      expect(find.text('Trainer 2'), findsOneWidget, reason: 'Trainer 2 should still be visible after stop');
      expect(find.byType(ListTile), findsNWidgets(2), reason: 'Both device ListTiles should still be visible');

      // But RSSI should show "Unknown" instead of numeric values
      expect(find.textContaining('RSSI: Unknown'), findsNWidgets(2));
      expect(find.textContaining('RSSI: -50'), findsNothing);
      expect(find.textContaining('RSSI: -60'), findsNothing);

      // Clean up
      scanner.dispose();
      platform.dispose();
    });

    testWidgets('devices become grayed out after stopping scan', (tester) async {
      // Create test infrastructure
      final platform = FakeBlePlatform();
      final permissions = FakeBlePermissions();
      final scanner = BleScanner(platform: platform, permissions: permissions);
      scanner.initialize();

      // Set up ready state
      platform.setAdapterState(fbp.BluetoothAdapterState.on);
      permissions.setHasPermission(true);
      permissions.setLocationServiceEnabled(true);

      // Build the widget with context_plus providing the scanner
      await tester.pumpWidget(
        ContextRef.root(
          child: Builder(
            builder: (context) {
              bleScannerRef.bind(context, () => scanner);
              return const MaterialApp(
                home: ScannerPage(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scanner should auto-start when ready
      expect(scanner.isScanning.value, isTrue);

      final device = platform.addDevice('00:11:22:33:44:55', 'Trainer 1', rssi: -50);
      device.turnOn();
      await tester.pumpAndSettle();

      // Find the ListTile while scanning
      final listTileWhileScanning = tester.widget<ListTile>(find.byType(ListTile));
      final iconWhileScanning = listTileWhileScanning.leading as Icon;

      // Icon should not be grayed out while scanning
      expect(iconWhileScanning.color, isNull); // null means default color

      // Stop scanning
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Find the ListTile after stopping
      final listTileAfterStop = tester.widget<ListTile>(find.byType(ListTile));
      final iconAfterStop = listTileAfterStop.leading as Icon;

      // Icon should be grayed out after stopping
      expect(iconAfterStop.color, equals(Colors.grey));

      // Clean up
      scanner.dispose();
      platform.dispose();
    });

    testWidgets('devices remain tappable after stopping scan', (tester) async {
      // Create test infrastructure
      final platform = FakeBlePlatform();
      final permissions = FakeBlePermissions();
      final scanner = BleScanner(platform: platform, permissions: permissions);
      scanner.initialize();

      // Set up ready state
      platform.setAdapterState(fbp.BluetoothAdapterState.on);
      permissions.setHasPermission(true);
      permissions.setLocationServiceEnabled(true);

      // Build the widget with context_plus providing the scanner
      await tester.pumpWidget(
        ContextRef.root(
          child: Builder(
            builder: (context) {
              bleScannerRef.bind(context, () => scanner);
              return const MaterialApp(
                home: ScannerPage(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scanner should auto-start when ready
      expect(scanner.isScanning.value, isTrue);

      final device = platform.addDevice('00:11:22:33:44:55', 'Trainer 1', rssi: -50);
      device.turnOn();
      await tester.pumpAndSettle();

      // Stop scanning
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Verify device is still visible
      expect(find.text('Trainer 1'), findsOneWidget);

      // Verify the device ListTile is still present and should be tappable
      // (We can't test actual navigation without GoRouter setup, but we can verify the widget exists)
      final listTile = tester.widget<ListTile>(find.byType(ListTile));
      expect(listTile.onTap, isNotNull, reason: 'Device should remain tappable after scan stops');

      // Clean up
      scanner.dispose();
      platform.dispose();
    });

    testWidgets('devices list updates when starting a new scan', (tester) async {
      // Create test infrastructure
      final platform = FakeBlePlatform();
      final permissions = FakeBlePermissions();
      final scanner = BleScanner(platform: platform, permissions: permissions);
      scanner.initialize();

      // Set up ready state
      platform.setAdapterState(fbp.BluetoothAdapterState.on);
      permissions.setHasPermission(true);
      permissions.setLocationServiceEnabled(true);

      // Build the widget with context_plus providing the scanner
      await tester.pumpWidget(
        ContextRef.root(
          child: Builder(
            builder: (context) {
              bleScannerRef.bind(context, () => scanner);
              return const MaterialApp(
                home: ScannerPage(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scanner should auto-start when ready
      expect(scanner.isScanning.value, isTrue);

      final device1 = platform.addDevice('00:11:22:33:44:55', 'Trainer 1', rssi: -50);
      device1.turnOn();
      await tester.pumpAndSettle();
      expect(find.text('Trainer 1'), findsOneWidget);

      // Stop first scan
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Device should still be visible with unknown RSSI
      expect(find.text('Trainer 1'), findsOneWidget);
      expect(find.textContaining('RSSI: Unknown'), findsOneWidget);

      // Start a new scan
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      // Add a different device
      device1.turnOff(); // Turn off old device
      final device2 = platform.addDevice('00:11:22:33:44:66', 'Trainer 2', rssi: -60);
      device2.turnOn();
      await tester.pumpAndSettle();

      // Now should see new device with live RSSI
      expect(find.text('Trainer 2'), findsOneWidget);
      expect(find.textContaining('RSSI: -60'), findsOneWidget);

      // Clean up
      scanner.dispose();
      platform.dispose();
    });
  });
}
