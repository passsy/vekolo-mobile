#!/bin/bash
# Test script for workout screen implementation
# Run this script to test all new workout screen components

set -e

echo "Testing workout screen implementation..."
echo ""

echo "1. Running power history model tests..."
puro flutter test test/domain/models/power_history_test.dart

echo ""
echo "2. Running workout power chart widget tests..."
puro flutter test test/widgets/workout_power_chart_test.dart

echo ""
echo "3. Running workout screen content widget tests..."
puro flutter test test/widgets/workout_screen_content_test.dart

echo ""
echo "4. Running all workout-related tests..."
puro flutter test test/services/workout_player_service_test.dart
puro flutter test test/domain/models/workout_session_test.dart
puro flutter test test/scenarios/workout_session_crash_recovery_test.dart
puro flutter test test/scenarios/workout_player_auto_pause_test.dart
puro flutter test test/services/workout_recording_service_test.dart
puro flutter test test/workout_models_test.dart
puro flutter test test/widgets/workout_resume_dialog_test.dart
puro flutter test test/services/workout_session_persistence_test.dart

echo ""
echo "All tests completed successfully!"
