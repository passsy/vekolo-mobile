- `DataSource` is a way to generic name
- Isn't the `ConnectionState` `error` the same as `disconnected`? Why the distinction. Maybe save the error, somewhere else as e.g. last connection issue with a timestamp and way more info?
- I think it is useful to use `CancelableOperation` for all connect() methods
- // TODO: Phase 4.2 - Implement device scanning | DONE - BleScanner implemented with dialog UI in DevicesPage
- Implement all other TODOs, except in example usage
- I can't actually connect my real Kickr core. allow me to do that.
- Rendering issue
======== Exception caught by rendering library =====================================================
The following assertion was thrown during layout:
A RenderFlex overflowed by 123 pixels on the right.

The relevant error-causing widget was:
Row Row:file:///Users/pascalwelsch/Projects/vekolo/vekolo-mobile/lib/pages/devices_page.dart:202:19
flutter: [WorkoutSyncService.syncTargetToDevice] Failed to set target power to 100W: Bad state: Device not connected
flutter: #0      MockTrainer.setTargetPower (package:vekolo/domain/mocks/mock_trainer.dart:145:7)
#1      WorkoutSyncService._syncTargetToDevice (package:vekolo/services/workout_sync_service.dart:244:21)
#2      WorkoutSyncService.startSync.<anonymous closure> (package:vekolo/services/workout_sync_service.dart:163:9)
#3      Subscription.update (package:state_beacon_core/src/consumers/subscription.dart:120:56)
#4      Subscription.updateIfNecessary (package:state_beacon_core/src/consumers/subscription.dart:96:7)
#5      _flushEffects (package:state_beacon_core/src/scheduler.dart:82:32)
#6      _asyncScheduler.<anonymous closure> (package:state_beacon_core/src/scheduler.dart:90:7)
#7      new Future.microtask.<anonymous closure> (dart:async/future.dart:287:40)
#8      _microtaskLoop (dart:async/schedule_microtask.dart:40:35)
#9      _startMicrotaskLoop (dart:async/schedule_microtask.dart:49:5)

- Can't connect a real device
  flutter: [WorkoutSyncService.syncTargetToDevice] Retrying in 1s (attempt 1/3)
  flutter: [WorkoutSyncService.syncTargetToDevice] Failed to set target power to 100W: Bad state: Device not connected
  flutter: #0      MockTrainer.setTargetPower (package:vekolo/domain/mocks/mock_trainer.dart:145:7)
  #1      WorkoutSyncService._syncTargetToDevice (package:vekolo/services/workout_sync_service.dart:244:21)
  #2      WorkoutSyncService._syncTargetToDevice (package:vekolo/services/workout_sync_service.dart:269:17)
  <asynchronous suspension>
  flutter: [WorkoutSyncService.syncTargetToDevice] Retrying in 2s (attempt 2/3)
  flutter: [WorkoutSyncService.syncTargetToDevice] Failed to set target power to 100W: Bad state: Device not connected
  flutter: #0      MockTrainer.setTargetPower (package:vekolo/domain/mocks/mock_trainer.dart:145:7)
  #1      WorkoutSyncService._syncTargetToDevice (package:vekolo/services/workout_sync_service.dart:244:21)
  #2      WorkoutSyncService._syncTargetToDevice (package:vekolo/services/workout_sync_service.dart:269:17)
  <asynchronous suspension>
  #3      WorkoutSyncService._syncTargetToDevice (package:vekolo/services/workout_sync_service.dart:269:11)
  <asynchronous suspension>
