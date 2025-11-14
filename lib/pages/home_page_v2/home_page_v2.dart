import 'package:context_plus/context_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:state_beacon/state_beacon.dart';
import 'package:vekolo/app/refs.dart';
import 'package:vekolo/pages/home_page_v2/home_page_controller.dart';
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

class _HomePage2State extends State<HomePage2> with SingleTickerProviderStateMixin {
  HomePageController? _controller;
  final _filterButtonKey = GlobalKey();
  final _overlayPortalController = OverlayPortalController();
  late AnimationController _modalAnimationController;
  bool _hasInitialized = false;
  bool _isModalShowing = false;
  Offset _filterButtonPosition = Offset.zero;
  Size _filterButtonSize = Size.zero;

  HomePageController get controller => _controller!;

  @override
  void initState() {
    super.initState();
    _modalAnimationController = AnimationController(duration: const Duration(milliseconds: 350), vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize controller and load activities once
    if (!_hasInitialized) {
      _hasInitialized = true;
      final apiClient = Refs.apiClient.of(context);
      final notificationService = Refs.notificationService.of(context);
      final workoutSessionPersistence = Refs.workoutSessionPersistence.of(context);
      _controller = HomePageController(
        apiClient: apiClient,
        notificationService: notificationService,
        workoutSessionPersistence: workoutSessionPersistence,
        context: context,
      );
      _controller!.loadActivities();
      _controller!.checkForIncompleteWorkouts();
    }
  }

  @override
  void dispose() {
    _modalAnimationController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _showFilterModal() {
    final RenderBox? renderBox = _filterButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    setState(() {
      _filterButtonPosition = renderBox.localToGlobal(Offset.zero);
      _filterButtonSize = renderBox.size;
      _isModalShowing = true;
    });

    // Reset animation to start
    _modalAnimationController.reset();
    _overlayPortalController.show();
    _modalAnimationController.forward();
  }

  Future<void> _closeFilterModal() async {
    await _modalAnimationController.reverse();
    _overlayPortalController.hide();
    setState(() {
      _isModalShowing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = controller.selectedTabIndex.watch(context);
    final authService = Refs.authService.of(context);
    final user = authService.currentUser.watch(context);
    final activeFilterColors = controller.activeFilterColors.watch(context);

    return OverlayPortal(
      controller: _overlayPortalController,
      overlayChildBuilder: (context) {
        final sourceFilter = controller.sourceFilter.watch(context);
        final workoutTypeFilters = controller.workoutTypeFilters.watch(context);

        return Stack(
          children: [
            // Animated backdrop
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _modalAnimationController,
                builder: (context, child) {
                  return GestureDetector(
                    onTap: _closeFilterModal,
                    child: Container(
                      color: Color.lerp(Colors.transparent, const Color(0x33000000), _modalAnimationController.value),
                    ),
                  );
                },
              ),
            ),
            // Animated filter popup
            Positioned(
              left: 16,
              top: _filterButtonPosition.dy + _filterButtonSize.height + 8,
              right: 16,
              child: AnimatedBuilder(
                animation: _modalAnimationController,
                builder: (context, child) {
                  final curvedValue = Curves.easeOutCubic.transform(_modalAnimationController.value);
                  final slideOffset = Offset(0, -40 * (1 - curvedValue));
                  return Transform.translate(
                    offset: slideOffset,
                    child: Opacity(
                      opacity: Tween<double>(
                        begin: 0.1,
                        end: 1.0,
                      ).evaluate(CurvedAnimation(parent: _modalAnimationController, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: FilterModal(
                    sourceFilter: sourceFilter,
                    workoutTypeFilters: workoutTypeFilters,
                    onSourceFilterChanged: (filter) {
                      controller.setSourceFilter(filter);
                    },
                    onWorkoutTypeToggled: (type) {
                      controller.toggleWorkoutType(type);
                    },
                    onClose: _closeFilterModal,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: PopScope(
        canPop: !_isModalShowing,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _isModalShowing) {
            _closeFilterModal();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Tab content
              IndexedStack(
                index: selectedIndex,
                children: [
                  ActivitiesTab(controller: controller, onFilterTap: _showFilterModal),
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
                  activeFilters: activeFilterColors,
                  filterButtonKey: _filterButtonKey,
                  onFilterTap: _showFilterModal,
                  onBookmarkTap: () {
                    // Switch to Library tab
                    controller.selectTab(1);
                  },
                  onDevicesTap: () {
                    context.push('/devices');
                  },
                  onProfileTap: () {
                    if (user != null) {
                      context.push('/profile');
                    } else {
                      context.push('/login');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
