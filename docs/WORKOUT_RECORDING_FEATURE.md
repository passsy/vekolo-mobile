# Workout Recording Feature

## Overview

The Vekolo app automatically records all your workout data while you exercise, saving every pedal stroke, heart beat, and power output. Your workout data is safely stored on your device and continues recording even if you need to close the app or if it crashes unexpectedly.

## What Gets Recorded

Every second during your workout, the app captures:

- **Power Output** - Your actual watts and the target watts from the workout plan
- **Heart Rate** - Your current BPM
- **Cadence** - Your pedaling RPM
- **Speed** - Your current speed (if available)
- **Workout Intensity** - Any adjustments you made to the power scale factor

All metrics include precise timestamps, allowing you to see exactly how your performance evolved throughout the session.

## Automatic Recording

### When Recording Starts

Recording begins automatically when your workout starts:

1. Open a workout
2. Start pedaling (when power reaches 40W, the workout auto-starts)
3. Recording begins immediately - no additional action needed

### Continuous Saving

Your workout data is saved continuously throughout your session:

- Metrics recorded every second
- Data automatically written to storage every few seconds
- No need to manually save - it happens in the background
- Storage is local on your device for privacy and offline capability

## App Crash Recovery

Life happens. Your phone might crash, run out of battery, or you might need to force-close the app. Don't worry - your workout data is safe.

### What Happens During a Crash

When the app unexpectedly closes during a workout:

1. All recorded data up to that point is preserved automatically
2. The app remembers which workout was in progress (stored separately from the workout files)
3. Your workout state is saved in the workout's metadata file (which block you were on, elapsed time, etc.)

**How it works behind the scenes:**
- The app keeps a simple marker ("this workout is active") that survives crashes
- When you restart the app, it checks this marker instantly (no scanning needed)
- If a marker exists, it loads that specific workout's details
- Resume dialog appears with all your workout info

### Resuming After a Crash

When you reopen the app after a crash or restart:

1. The app detects the interrupted workout session
2. A dialog appears with your workout details:
   - Workout name
   - How much time had elapsed
   - When the last data was recorded
3. You have three options:

**Option 1: Resume Workout**
- Continues exactly where you left off
- Preserves your elapsed time and progress
- Picks up recording seamlessly
- Your workout file shows no gap (except for the time you were stopped)

**Option 2: Discard Session**
- Keeps all the data recorded before the crash
- Marks the workout as "incomplete" or "abandoned"
- Useful if you don't plan to finish the workout

**Option 3: Start Fresh**
- Discards the interrupted session data
- Starts a new workout from the beginning
- Useful if the crash happened very early in your workout

### Viewing Incomplete Workouts

Even if you don't complete a workout:

- All recorded data is preserved
- Incomplete sessions are marked with a special status
- You can review the data later to analyze what you did complete
- Useful for interrupted sessions, testing equipment, or warm-ups

## Technical Notes

- Recording frequency: 1 sample per second (1 Hz)
- Stale data threshold: 5 seconds without sensor update
- Storage format: JSON (human-readable, easy to export)
- Timestamp precision: Milliseconds
- Memory efficient: Samples written to disk periodically, not kept in RAM
