import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/location_service.dart';
import '../services/home_service.dart';
import '../widgets/provider_bottom_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  LatLng? _userLocation;
  bool _isLoadingLocation = true;
  bool _locationDenied = false;

  // Search state
  String _searchQuery = '';
  double _radiusKm = 10;
  bool _isMapView = true;
  List<String> _popularServices = [];
  List<ProviderCardData> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _hasMore = false;
  String? _nextCursor;
  bool _isLoadingMore = false;
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _getLocation();
    _loadPopularServices();
    _listScrollController.addListener(_onListScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    try {
      final location = await _locationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _userLocation = location;
          _isLoadingLocation = false;
        });
      }
    } on LocationPermissionException {
      if (mounted) setState(() { _locationDenied = true; _isLoadingLocation = false; });
    } catch (e) {
      if (mounted) setState(() { _locationDenied = true; _isLoadingLocation = false; });
    }
  }

  Future<void> _loadPopularServices() async {
    try {
      final doc = await _firestore.collection('metadata').doc('service_counts').get();
      if (doc.exists && mounted) {
        final counts = doc.data() ?? {};
        final sorted = counts.entries.toList()
          ..sort((a, b) => (b.value as num).compareTo(a.value as num));
        setState(() {
          _popularServices = sorted.take(6).map((e) => e.key).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _search({String? cursor}) async {
    if (_searchQuery.isEmpty || _userLocation == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final result = await _supabase.rpc('search_providers', params: {
        'user_lat': _userLocation!.latitude,
        'user_lng': _userLocation!.longitude,
        'p_service': _searchQuery,
        'p_radius_meters': (_radiusKm * 1000).toInt(),
        'p_cursor': cursor,
        'p_limit': 10,
      });

      if (result == null || (result as List).isEmpty) {
        if (cursor == null) _results = [];
        setState(() {
          _hasMore = false;
          _nextCursor = null;
          _isSearching = false;
        });
        return;
      }

      final rows = result as List;
      final uids = rows.map((r) => r['id'] as String).toList();
      final distances = Map<String, double>.fromEntries(
        rows.map((r) => MapEntry(r['id'] as String, (r['distance_meters'] as num).toDouble())),
      );

      final hasMore = rows.length > 10;
      final fetchUids = hasMore ? uids.sublist(0, 10) : uids;

      // Batch read from Firestore
      final profiles = <ProviderCardData>[];
      for (int i = 0; i < fetchUids.length; i += 10) {
        final chunk = fetchUids.sublist(i, i + 10 > fetchUids.length ? fetchUids.length : i + 10);
        final snapshot = await _firestore
            .collection('profiles')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          profiles.add(ProviderCardData(
            uid: doc.id,
            name: data['name'] ?? '',
            photoUrl: data['photoUrl'] ?? '',
            rating: (data['rating'] ?? 0.0).toDouble(),
            reviewCount: (data['reviewCount'] ?? 0).toInt(),
            services: List<String>.from(data['services'] ?? []),
            distance: distances[doc.id] ?? 0.0,
            gigCount: (data['gigCount'] ?? 0).toInt(),
            gigCount7Days: (data['gigCount7Days'] ?? 0).toInt(),
            gigCount30Days: (data['gigCount30Days'] ?? 0).toInt(),
            workspaceAddress: data['workspaceAddress'] ?? '',
            workspaceLat: (data['workspaceLat'] ?? 0.0).toDouble(),
            workspaceLng: (data['workspaceLng'] ?? 0.0).toDouble(),
          ));
        }
      }

      // Sort: distance ASC → activity → rating → gigs
      profiles.sort((a, b) {
        final d = a.distance.compareTo(b.distance);
        if (d != 0) return d;
        final aActive = a.gigCount7Days >= 1 || a.gigCount30Days >= 3;
        final bActive = b.gigCount7Days >= 1 || b.gigCount30Days >= 3;
        final act = (bActive ? 1 : 0).compareTo(aActive ? 1 : 0);
        if (act != 0) return act;
        final r = b.rating.compareTo(a.rating);
        if (r != 0) return r;
        return b.gigCount.compareTo(a.gigCount);
      });

      if (mounted) {
        setState(() {
          if (cursor == null) {
            _results = profiles;
          } else {
            _results.addAll(profiles);
          }
          _hasMore = hasMore;
          _nextCursor = hasMore ? fetchUids.last : null;
          _isSearching = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isSearching = false; _isLoadingMore = false; });
      }
    }
  }

  void _onListScroll() {
    if (_listScrollController.position.pixels >= _listScrollController.position.maxScrollExtent - 300) {
      if (!_isLoadingMore && _hasMore) {
        _isLoadingMore = true;
        _search(cursor: _nextCursor);
      }
    }
  }

  void _onServiceChipTap(String service) {
    _searchController.text = service;
    _searchQuery = service;
    _search();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _results = [];
      _hasSearched = false;
    });
  }

  void _onMarkerTap(ProviderCardData provider) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProviderBottomSheet(provider: provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Map
            if (_isMapView && !_locationDenied && _userLocation != null)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _userLocation!,
                  initialZoom: 13.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gigscourt.app',
                  ),
                  // Provider markers
                  if (_results.isNotEmpty)
                    MarkerLayer(
                      markers: _results.map((p) {
                        final isActive = p.gigCount7Days >= 1;
                        return Marker(
                          point: LatLng(p.workspaceLat, p.workspaceLng),
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => _onMarkerTap(p),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isActive ? const Color(0xFF4CAF50) : Colors.white,
                                  width: isActive ? 3 : 2,
                                ),
                                boxShadow: [BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 4)],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: CachedNetworkImage(
                                  imageUrl: p.photoUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: Theme.of(context).cardColor,
                                    child: Icon(Icons.person, size: 20, color: Theme.of(context).textTheme.bodySmall?.color),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),

            // List View
            if (!_isMapView)
              _buildListView(),

            // Controls overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),

            // Location denied
            if (_locationDenied)
              _buildLocationDenied(),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withAlpha(230),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search input + toggle
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => _searchQuery = v,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search services...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _clearSearch,
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Map/List toggle
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _toggleButton(Icons.map_outlined, _isMapView, () => setState(() => _isMapView = true)),
                    _toggleButton(Icons.list_outlined, !_isMapView, () => setState(() => _isMapView = false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Radius slider
          Row(
            children: [
              const Text('Radius:', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              Expanded(
                child: Slider(
                  value: _radiusKm,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  activeColor: const Color(0xFF1A1F71),
                  label: '${_radiusKm.round()}km',
                  onChanged: (v) => setState(() => _radiusKm = v),
                  onChangeEnd: (_) => _hasSearched ? _search() : null,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F71),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_radiusKm.round()}km',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
          // Popular services chips
          if (_popularServices.isNotEmpty)
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _popularServices.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final service = _popularServices[index];
                  return GestureDetector(
                    onTap: () => _onServiceChipTap(service),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _searchQuery == service
                            ? const Color(0xFF1A1F71)
                            : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A1F71).withAlpha(51)),
                      ),
                      child: Text(
                        service.replaceAll('-', ' '),
                        style: TextStyle(
                          fontSize: 11,
                          color: _searchQuery == service ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _toggleButton(IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? const Color(0xFF1A1F71) : Colors.transparent,
        ),
        child: Icon(icon, size: 18, color: isActive ? Colors.white : const Color(0xFF6B7280)),
      ),
    );
  }

  Widget _buildListView() {
    if (!_hasSearched) {
      return Center(
        child: Text(
          'Search for a service above or pick from popular services to find providers near you.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13),
        ),
      );
    }

    if (_isSearching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Color(0xFF6B7280)),
            const SizedBox(height: 16),
            Text(
              'No providers offer ${_searchQuery.replaceAll('-', ' ')} in this area.\nYou could be the first!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _listScrollController,
      padding: const EdgeInsets.only(top: 160, bottom: 40),
      itemCount: _results.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
        }
        final p = _results[index];
        final isActive = p.gigCount7Days >= 1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: GestureDetector(
            onTap: () => _onMarkerTap(p),
            child: Container(
              height: 85,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: NetworkImage(p.photoUrl),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, Colors.black.withAlpha(180)],
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            if (isActive)
                              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4CAF50),
                                  boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withAlpha(77), blurRadius: 4)])),
                            Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.star, size: 11, color: Colors.amber),
                            Text(' ${p.rating.toStringAsFixed(1)} (${p.reviewCount})', style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ]),
                          const SizedBox(height: 2),
                          Text('${_formatDistance(p.distance)} · ${p.gigCount30Days} gigs this month',
                            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 48, color: Color(0xFF6B7280)),
            const SizedBox(height: 16),
            const Text('Location Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enable location to search for providers near you.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _getLocation, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}
