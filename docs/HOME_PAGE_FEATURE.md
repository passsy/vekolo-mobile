# Home Page Feature

## Overview

The home page is the main entry point of the Vekolo app, providing access to workouts through a three-tab interface. Users can discover community workouts, manage their saved workouts, and access workout creation tools.

**Design References:**
- Activities screen: `docs/designs/Activities.png`
- Activities with tabs: `docs/designs/Activities with tabs.png`
- Filter modal: `docs/designs/Filter 13.png`

## Tab Structure

### 1. Activities Tab

The Activities tab is the primary discovery and activity tracking hub. It displays a scrollable list of workout cards showing workouts from multiple sources.

#### Visual Design

**Page Title**
- "Activities" displayed at top in orange/red accent color
- Large, italic, stylized font

**Top Bar (Alternative Design)**
- Bookmark icon (left) - Quick access to Workout Library tab
- Filter button (center) - Opens filter modal with colorful interval bars icon
- Devices icon (right) - Manage bluetooth devices
- Profile picture (right) - User profile/settings

**Workout Cards**
- Rounded corners with dark background
- **Header Section:**
  - Author avatar (left) and name
  - Date posted/completed (right)
- **Main Content:**
  - Workout title in large, bold text (e.g., "Over Under Forge", "Iron Mountain")
  - Duration displayed prominently on the right
  - Workout type label below title (e.g., "threshold", "saturation")
  - Colorful interval visualization bars showing workout structure (blue, green, orange, pink)
- **Statistics Grid (4 columns):**
  - Row 1: Ø PPM, Ø RPM, Ø km/H, Max Km/H (primary metrics)
  - Row 2: Zeit (time), KM, Watt, Kalorien (totals)
  - Labels shown in light gray below values
- Cards scroll vertically in a feed layout with spacing between cards

#### Content Sources

**Community Workouts**
- All publicly available workouts from the Vekolo community (default view)
- Each workout card shows all visual elements described above

**My Workouts**
- User's own created workouts appear in the same feed
- Filter to "Bookmarked" shows only saved workouts

**Active Workout Recovery Card**
- If the app crashed or was closed during an active workout, a special workout card appears at the top of the Activities tab
- This card displays:
  - The workout that was in progress
  - Last known position in the workout
  - "Resume" button to continue where they left off
  - "Dismiss" option to abandon the session
- This replaces the previous dialog-based approach for better visibility and context

**Completed Workouts**
- Workouts that the user has completed appear in the feed
- These are stored locally on the device
- Each completed workout card shows:
  - Workout name
  - Completion date and time
  - Duration and statistics (distance, calories, etc.)
  - Option to view detailed results
  - Option to repeat the workout
- Note: At this time, completed workouts are only available locally. Cloud sync and sharing features are planned for future releases.

#### Filtering and Sorting

**Filter Modal**
- Opens when tapping the filter button in the top bar
- Dark modal overlay with rounded corners
- Two filter sections:

**Source Filters (Toggle)**
- "Everybody" - Shows all community workouts (default)
- "Bookmarked" - Shows only saved/favorited workouts
- Toggle button with icon: crossed-out circle for Everybody, bookmark for Bookmarked
- Selected option highlighted in orange

**Workout Type Filters (Multi-select)**
- RECOVERY - Wave icon
- ENDURANCE - Heart rate icon
- TEMPO - Fast-forward icon
- THRESHOLD - Lightning bolt icon
- VO2MAX - Flame icon
- FTP - Rocket icon
- Selected types highlighted in orange/pink
- Multiple types can be selected simultaneously
- Unselected types shown in dark gray

**Sorting**
- Default: Chronological order (newest first)
- Completed workouts sorted by completion date

#### User Interactions

- Tap any workout card to view full workout details
- Swipe to reveal quick actions (favorite, share, etc.)
- Pull-to-refresh to get latest community workouts
- Scroll to load more workouts (infinite scroll)

---

### 2. Workout Library Tab

The Workout Library tab provides quick access to workouts the user has saved for easy access.

#### Purpose

This tab serves as a personal collection of favorite workouts, making it easy to find and start preferred workouts without searching through the community feed.

#### Content

**Saved Workouts**
- All workouts the user has favorited/saved
- Includes both:
  - Community workouts they've saved
  - Their own created workouts
- Each workout card displays the same information as in the Activities tab

**Organization**
- Workouts are displayed in a grid or list view
- Default sorting: Recently saved first
- Future: Support for custom collections/folders

#### User Interactions

- Tap to view workout details and start workout
- Long-press or swipe for quick actions:
  - Remove from library
  - Share
  - Create a copy to edit
- Empty state message when no workouts are saved, with call-to-action to explore community workouts

---

### 3. Create Workout Tab

The Create Workout tab will provide tools for users to design their own custom workouts.

#### Current Status

**Coming Soon**
- This tab is currently in development
- A placeholder message informs users that workout creation tools are coming soon
- May include a waitlist signup or notification request feature

#### Planned Features

**Workout Builder**
- Visual interface to design workout structure
- Add intervals, sets, and rest periods
- Set target metrics (power, heart rate, cadence)
- Preview workout profile graph

**Templates**
- Start from pre-built workout templates
- Copy and modify existing workouts
- Save as personal templates

**Testing**
- Preview mode to test workout before saving
- Ability to simulate workout progression

---

## Navigation

**Liquid Glass Tab Bar**
- Fixed bottom tab bar in pill-shaped container
- Frosted glass/blur effect with dark semi-transparent background
- Rounded corners creating a floating pill appearance
- Centered horizontally with padding from screen edges
- Three tabs with icons above labels:
  - **Activities**: Stacked layers icon - Shows all workouts and activity feed
  - **Builder/Library**: Bookmark/folder icon - Workout library or builder
  - **Create**: Plus/add icon (may be shown as floating action button)
- Active tab highlighted with orange/red accent color
- Icon and label both colored when active
- Inactive tabs shown in light gray/white
- Smooth, fluid animations on tab switching

**Floating Action Button**
- Orange circular button with lightning bolt icon
- Positioned to the right of the tab bar
- Likely for quick workout start or other primary action
- Maintains visibility when scrolling

**Tab Switching**
- Tap any tab to switch
- Tab state is preserved when switching (scroll position, filters)
- Smooth transitions between tabs with liquid animation effect

**Quick Navigation**
- Bookmark icon in Activities top bar (alternative design) provides quick jump to Workout Library
- Maintains current tab bar position for easy return

---

## User Workflows

### Discovering and Starting a Workout

1. Open app → Activities tab (default)
2. Browse community workouts or filter to "Only Mine"
3. Tap workout card to view details
4. Tap "Start Workout" button
5. Follow workout on device

### Resuming After Crash

1. Open app → Activities tab
2. Active workout recovery card appears at top
3. Review last known position
4. Tap "Resume" to continue workout
5. OR tap "Dismiss" to abandon session

### Managing Saved Workouts

1. Switch to Workout Library tab
2. Browse saved workouts
3. Tap to start or view details
4. Swipe to remove from library if no longer needed

### Viewing Completed Workouts

1. Activities tab displays completed workout cards
2. Tap completed workout to view detailed results:
   - Performance graphs
   - Split times
   - Heart rate zones
   - Power distribution
3. Option to share results (future feature)
4. Option to repeat the same workout

---

## Edge Cases and Special Behaviors

### Empty States

**Activities Tab**
- First-time users see welcome message with guidance
- Empty state when no community workouts available (network issue)

**Workout Library Tab**
- Clear message when no workouts saved
- Call-to-action button to explore Activities tab

**Completed Workouts**
- "No completed workouts yet" message for new users
- Encouragement to start first workout

### Network Connectivity

**Offline Behavior**
- Activities tab shows cached community workouts
- Banner indicates offline status
- Saved workouts in Library tab always available
- Completed workouts always available (stored locally)

**Online Sync**
- Automatic refresh when connection restored
- Pull-to-refresh manually syncs latest content

### Crash Recovery

**Workout in Progress**
- App detects incomplete workout session on launch
- Recovery card appears automatically in Activities tab
- Session data preserved including:
  - Current position
  - Elapsed time
  - Completed intervals
  - Performance data

---

## Future Enhancements

### Activities Tab
- Social features: likes, comments on workouts
- Trending/popular workouts section
- Personalized recommendations based on history

### Workout Library Tab
- Custom collections/folders
- Smart collections (e.g., "Short workouts", "High intensity")
- Sharing collections with friends

### Create Workout Tab
- Full workout builder implementation
- AI-assisted workout generation
- Import workouts from files
- Export/share custom workouts

### Completed Workouts
- Cloud sync and backup
- Share results to social media
- Compare performance across multiple attempts
- Training analytics and trends
