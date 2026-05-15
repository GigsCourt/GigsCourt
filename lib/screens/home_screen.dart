import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notifications_screen.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/home_service.dart';
import '../widgets/trending_section.dart';
import '../widgets/nearby_section.dart';
import '../widgets/provider_bottom_sheet.dart';
import '../utils/error_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final LocationService _locationService = LocationService();
  final HomeService _homeService = HomeService();
  final AuthService _authService = AuthService();

  bool _isCollapsed = false;

  LatLng? _userLocation;
  bool _locationDenied = false;

  List<ProviderCardData> _trendingProviders = [];
  List<ProviderCardData> _nearbyProviders = [];
  bool _trendingHasMore = true;
  bool _nearbyHasMore = true;
  String? _trendingCursor;
  String? _nearbyCursor;
  bool _isInitialLoad = true;
  bool _isFetching = false;

  int _unreadCount = 0;
  StreamSubscription? _notificationSubscription;
  StreamSubscription<LatLng>? _locationStreamSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _notificationSubscription?.cancel();
    _locationStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgroundRefresh();
    }
  }

  Future<void> _initialize() async {
    await _loadCachedData();
    _listenToNotifications();

    try {
      _userLocation = await _locationService.getLocation();
      if (mounted) {
        setState(() => _locationDenied = false);
        _listenToLocationChanges();
        _fetchFreshData();
      }
    } on LocationPermissionException {
      if (mounted) setState(() => _locationDenied = true);
    } catch (e) {
      if (mounted) setState(() => _locationDenied = true);
    }
  }

  Future<void> _loadCachedData() async {
    final cachedTrending = await _homeService.getCachedTrending();
    final cachedNearby = await _homeService.getCachedNearby();

    if (mounted && (cachedTrending.isNotEmpty || cachedNearby.isNotEmpty)) {
      setState(() {
        _trendingProviders = cachedTrending;
        _nearbyProviders = cachedNearby;
        _isInitialLoad = false;
      });
    }
  }

  void _listenToNotifications() {
    final user = _authService.currentUser;
    if (user == null) return;

    _notificationSubscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) setState(() => _unreadCount = snapshot.docs.length);
    });
  }

  void _listenToLocationChanges() {
    _locationStreamSubscription = _locationService.locationStream.listen((newLocation) {
      if (mounted) {
        _userLocation = newLocation;
        _fetchFreshData();
      }
    });
  }

  Future<void> _fetchFreshData() async {
    if (_userLocation == null || _isFetching) return;
    _isFetching = true;

    try {
      final trendingResult = await _homeService.fetchTrending(userLocation: _userLocation!);
      final nearbyResult = await _homeService.fetchNearby(userLocation: _userLocation!);

      if (mounted) {
        setState(() {
          _trendingProviders = trendingResult.providers;
          _trendingCursor = trendingResult.nextCursor;
          _trendingHasMore = trendingResult.hasMore;
          _nearbyProviders = nearbyResult.providers;
          _nearbyCursor = nearbyResult.nextCursor;
          _nearbyHasMore = nearbyResult.hasMore;
          _isInitialLoad = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _backgroundRefresh() async {
    try {
      _userLocation = await _locationService.getLocation();
      if (mounted) _fetchFreshData();
    } catch (_) {}
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    try {
      _userLocation = await _locationService.getLocation();
    } catch (_) {}
    _trendingCursor = null;
    _nearbyCursor = null;
    await _fetchFreshData();
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _onScroll() {
    final collapsed = _scrollController.hasClients && _scrollController.offset > 80;
    if (collapsed != _isCollapsed) {
      HapticFeedback.selectionClick();
      setState(() => _isCollapsed = collapsed);
    }
  }

  Future<PaginatedResult> _onTrendingFetchMore(String? cursor) async {
    if (_userLocation == null) return PaginatedResult(providers: [], nextCursor: null, hasMore: false);
    return _homeService.fetchTrending(userLocation: _userLocation!, cursor: cursor);
  }

  Future<PaginatedResult> _onNearbyFetchMore(String? cursor) async {
    if (_userLocation == null) return PaginatedResult(providers: [], nextCursor: null, hasMore: false);
    return _homeService.fetchNearby(userLocation: _userLocation!, cursor: cursor);
  }

  void _onProviderTap(ProviderCardData provider) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProviderBottomSheet(provider: provider),
    );
  }

  void _openLocationSettings() {
    if (Platform.isIOS) {
      launchUrl(Uri.parse('app-settings:'));
    } else {
      launchUrl(Uri.parse('android.settings.LOCATION_SOURCE_SETTINGS'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _locationDenied ? _buildLocationDenied() : _buildContent(),
      ),
    );
  }

  Widget _buildLocationDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Color(0xFF6B7280)),
            const SizedBox(height: 24),
            const Text('Location Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'GigsCourt needs your location to show providers near you.\nPlease enable location services to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                try {
                  _userLocation = await _locationService.getLocation();
                  if (mounted) {
                    setState(() => _locationDenied = false);
                    _listenToLocationChanges();
                    _fetchFreshData();
                  }
                } catch (_) {}
              },
              child: const Text('Try Again'),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _openLocationSettings, child: const Text('Open Settings')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: _isCollapsed ? 10 : 20),
              child: _isCollapsed ? _buildCollapsedHeader() : _buildExpandedHeader(),
            ),
            if (_isCollapsed) const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: _isInitialLoad
                  ? _buildShimmer()
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      color: const Color(0xFF1A1F71),
                      child: ListView(
                        key: const PageStorageKey('home_list'),
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 16),
                          TrendingSection(
                            initialProviders: _trendingProviders,
                            hasMore: _trendingHasMore,
                            nextCursor: _trendingCursor,
                            onFetchMore: _onTrendingFetchMore,
                            onProviderTap: _onProviderTap,
                          ),
                          const SizedBox(height: 24),
                          NearbySection(
                            initialProviders: _nearbyProviders,
                            hasMore: _nearbyHasMore,
                            nextCursor: _nearbyCursor,
                            onFetchMore: _onNearbyFetchMore,
                            onProviderTap: _onProviderTap,
                            parentScrollController: _scrollController,
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
            ),
          ],
        ),
        if (_scrollController.hasClients && _scrollController.offset > 200)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              onPressed: () {
                _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              },
              backgroundColor: const Color(0xFF1A1F71),
              child: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gigs', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.1)),
            Text('Court', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.1)),
          ],
        ),
        _buildBellIcon(),
      ],
    );
  }

  Widget _buildCollapsedHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 24),
        const Text('GigsCourt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        _buildBellIcon(),
      ],
    );
  }

  Widget _buildBellIcon() {
    return Stack(
      children: [
        IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          },
          icon: const Icon(Icons.notifications_outlined),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 6, top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1F71)),
              child: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildShimmer() {
    return const Center(child: CircularProgressIndicator());
  }
}
