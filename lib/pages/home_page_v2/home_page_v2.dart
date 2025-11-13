import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/pages/home_page_v2/home_page_state.dart';
import 'package:vekolo/pages/home_page_v2/tabs/activities_tab.dart';
import 'package:vekolo/pages/home_page_v2/tabs/create_tab.dart';
import 'package:vekolo/pages/home_page_v2/tabs/library_tab.dart';
import 'package:vekolo/pages/home_page_v2/widgets/filter_modal.dart';
import 'package:vekolo/pages/home_page_v2/widgets/home_top_bar.dart';
import 'package:vekolo/pages/home_page_v2/widgets/liquid_glass_tab_bar.dart';

/// New home page with tab navigation and activities feed
class HomePage2 extends StatefulWidget {
  const HomePage2({super.key});

  @override
  State<HomePage2> createState() => _HomePage2State();
}

class _HomePage2State extends State<HomePage2> {
  late final state = HomePageState();
  final _filterButtonKey = GlobalKey();
  OverlayEntry? _filterOverlay;

  @override
  void dispose() {
    _filterOverlay?.remove();
    _filterOverlay = null;
    state.dispose();
    super.dispose();
  }

  void _showFilterModal() {
    // Remove existing overlay if any
    _filterOverlay?.remove();

    final RenderBox? renderBox = _filterButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _filterOverlay = OverlayEntry(
      builder: (context) {
        final sourceFilter = state.sourceFilter.watch(context);
        final workoutTypeFilters = state.workoutTypeFilters.watch(context);

        return Stack(
          children: [
            // Backdrop to detect taps outside
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFilterModal,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Filter popup
            Positioned(
              left: 16,
              top: position.dy + size.height + 8,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: FilterModal(
                  sourceFilter: sourceFilter,
                  workoutTypeFilters: workoutTypeFilters,
                  onSourceFilterChanged: (filter) {
                    state.setSourceFilter(filter);
                  },
                  onWorkoutTypeToggled: (type) {
                    state.toggleWorkoutType(type);
                  },
                  onClose: _closeFilterModal,
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_filterOverlay!);
  }

  void _closeFilterModal() {
    _filterOverlay?.remove();
    _filterOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = state.selectedTabIndex.watch(context);
    final authService = Refs.authService.of(context);
    final user = authService.currentUser.watch(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Tab content
          IndexedStack(
            index: selectedIndex,
            children: [
              ActivitiesTab(onFilterTap: _showFilterModal),
              const LibraryTab(),
              const CreateTab(),
            ],
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: HomeTopBar(
              user: user,
              filterButtonKey: _filterButtonKey,
              onFilterTap: _showFilterModal,
              onBookmarkTap: () {
                // Switch to Library tab
                state.selectTab(1);
              },
              onDevicesTap: () {
                context.push('/devices');
              },
              onProfileTap: () {
                context.push('/profile');
              },
            ),
          ),

          // Liquid glass tab bar at bottom
          Positioned(
            left: 0,
            bottom: 0,
            child: LiquidGlassTabBar(
              selectedIndex: selectedIndex,
              onTabSelected: (index) => state.selectTab(index),
              tabs: const [
                TabItem(icon: Icons.layers, label: 'Activities'),
                TabItem(icon: Icons.bookmark, label: 'Library'),
                TabItem(icon: Icons.add, label: 'Create'),
              ],
            ),
          ),

          // Floating action button (lightning bolt)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () {
                // TODO: Quick start workout action
              },
              backgroundColor: const Color(0xFFFF6F00),
              child: const Icon(Icons.bolt, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}
