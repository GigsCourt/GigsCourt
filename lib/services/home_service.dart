import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';

class HomeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _trendingCacheKey = 'home_trending_cache';
  static const String _nearbyCacheKey = 'home_nearby_cache';
  static const int _pageSize = 10;
  static const int _nearbyMaxResults = 50;
  static const int _trendingMaxResults = 50;

  Future<List<ProviderCardData>> getCachedTrending() async {
    return _getCached(_trendingCacheKey);
  }

  Future<List<ProviderCardData>> getCachedNearby() async {
    return _getCached(_nearbyCacheKey);
  }

  Future<PaginatedResult> fetchTrending({
    required LatLng userLocation,
    String? cursor,
  }) async {
    return _fetchProviders(
      userLocation: userLocation,
      cursor: cursor,
      cacheKey: _trendingCacheKey,
      maxResults: _trendingMaxResults,
      filterTrending: true,
    );
  }

  Future<PaginatedResult> fetchNearby({
    required LatLng userLocation,
    String? cursor,
  }) async {
    return _fetchProviders(
      userLocation: userLocation,
      cursor: cursor,
      cacheKey: _nearbyCacheKey,
      maxResults: _nearbyMaxResults,
      filterTrending: false,
    );
  }

  Future<PaginatedResult> _fetchProviders({
    required LatLng userLocation,
    String? cursor,
    required String cacheKey,
    required int maxResults,
    required bool filterTrending,
  }) async {
    final supabaseResult = await _supabase.rpc('get_nearby_profiles', params: {
      'user_lat': userLocation.latitude,
      'user_lng': userLocation.longitude,
      'p_cursor': cursor,
      'p_limit': _pageSize,
      'p_max_results': maxResults,
    });

    if (supabaseResult == null || (supabaseResult as List).isEmpty) {
      return PaginatedResult(providers: [], nextCursor: null, hasMore: false);
    }

    final List<dynamic> rows = supabaseResult;
    final uids = rows.map((r) => (r['id'] ?? '').toString()).where((id) => id.isNotEmpty).toList();
    final distances = <String, double>{};
    for (final r in rows) {
      final id = (r['id'] ?? '').toString();
      if (id.isNotEmpty) {
        distances[id] = ((r['distance_meters'] ?? 0) as num).toDouble();
      }
    }

    final hasMore = rows.length > _pageSize;
    final fetchUids = hasMore ? uids.sublist(0, _pageSize) : uids;
    final nextCursor = hasMore ? fetchUids.last : null;

    final firestoreData = await _batchReadProfiles(fetchUids);

    final providers = _mergeAndSort(firestoreData, distances, userLocation, filterTrending);

    if (cursor == null && providers.isNotEmpty) {
      _cacheProviders(cacheKey, providers);
    }

    return PaginatedResult(
      providers: providers,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _batchReadProfiles(List<String> uids) async {
    final result = <String, Map<String, dynamic>>{};

    for (int i = 0; i < uids.length; i += 10) {
      final chunk = uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10);
      final snapshot = await _firestore
          .collection('profiles')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        result[doc.id] = doc.data();
      }
    }

    return result;
  }

  List<ProviderCardData> _mergeAndSort(
    Map<String, Map<String, dynamic>> firestoreData,
    Map<String, double> distances,
    LatLng userLocation,
    bool filterTrending,
  ) {
    final providers = <ProviderCardData>[];

    for (final entry in firestoreData.entries) {
      final uid = entry.key;
      final data = entry.value;
      final distance = distances[uid] ?? 0.0;

      final gigCount7Days = (data['gigCount7Days'] ?? 0).toInt();
      final gigCount30Days = (data['gigCount30Days'] ?? 0).toInt();
      final reviewCount = (data['reviewCount'] ?? 0).toInt();
      final rating = (data['rating'] ?? 0.0).toDouble();
      final gigCount = (data['gigCount'] ?? 0).toInt();
      final services = List<String>.from(data['services'] ?? []);

      providers.add(ProviderCardData(
        uid: uid,
        name: data['name'] ?? '',
        photoUrl: data['photoUrl'] ?? '',
        rating: rating,
        reviewCount: reviewCount,
        services: services,
        distance: distance,
        gigCount: gigCount,
        gigCount7Days: gigCount7Days,
        gigCount30Days: gigCount30Days,
        workspaceAddress: data['workspaceAddress'] ?? '',
        workspaceLat: (data['workspaceLat'] ?? 0.0).toDouble(),
        workspaceLng: (data['workspaceLng'] ?? 0.0).toDouble(),
      ));
    }

    if (filterTrending) {
      // Trending: only show active providers with reviews
      providers.removeWhere((p) => p.gigCount7Days < 1 || p.reviewCount < 1);
      // Sort: distance first, then activity, then rating, then total gigs
      providers.sort((a, b) {
        final distanceCompare = a.distance.compareTo(b.distance);
        if (distanceCompare != 0) return distanceCompare;
        final aActive = a.gigCount7Days >= 1 || a.gigCount30Days >= 3;
        final bActive = b.gigCount7Days >= 1 || b.gigCount30Days >= 3;
        final activityCompare = (bActive ? 1 : 0).compareTo(aActive ? 1 : 0);
        if (activityCompare != 0) return activityCompare;
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.gigCount.compareTo(a.gigCount);
      });
    } else {
      // Nearby: distance first, then activity, then rating, then total gigs
      providers.sort((a, b) {
        final distanceCompare = a.distance.compareTo(b.distance);
        if (distanceCompare != 0) return distanceCompare;
        final aActive = a.gigCount7Days >= 1 || a.gigCount30Days >= 3;
        final bActive = b.gigCount7Days >= 1 || b.gigCount30Days >= 3;
        final activityCompare = (bActive ? 1 : 0).compareTo(aActive ? 1 : 0);
        if (activityCompare != 0) return activityCompare;
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.gigCount.compareTo(a.gigCount);
      });
    }

    return providers;
  }

  Future<void> _cacheProviders(String key, List<ProviderCardData> providers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = providers.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(key, jsonList);
    } catch (_) {
      // Silently fail — cache is non-critical
    }
  }

  Future<List<ProviderCardData>> _getCached(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(key);
      if (jsonList == null || jsonList.isEmpty) return [];
      return jsonList
          .map((j) => ProviderCardData.fromJson(jsonDecode(j)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class ProviderCardData {
  final String uid;
  final String name;
  final String photoUrl;
  final double rating;
  final int reviewCount;
  final List<String> services;
  final double distance;
  final int gigCount;
  final int gigCount7Days;
  final int gigCount30Days;
  final String workspaceAddress;
  final double workspaceLat;
  final double workspaceLng;

  ProviderCardData({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.rating,
    required this.reviewCount,
    required this.services,
    required this.distance,
    required this.gigCount,
    required this.gigCount7Days,
    required this.gigCount30Days,
    required this.workspaceAddress,
    required this.workspaceLat,
    required this.workspaceLng,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'photoUrl': photoUrl,
        'rating': rating,
        'reviewCount': reviewCount,
        'services': services,
        'distance': distance,
        'gigCount': gigCount,
        'gigCount7Days': gigCount7Days,
        'gigCount30Days': gigCount30Days,
        'workspaceAddress': workspaceAddress,
        'workspaceLat': workspaceLat,
        'workspaceLng': workspaceLng,
      };

  factory ProviderCardData.fromJson(Map<String, dynamic> json) {
    return ProviderCardData(
      uid: json['uid'] ?? '',
      name: json['name'] ?? '',
      photoUrl: json['photoUrl'] ?? '',
      rating: (json['rating'] ?? 0.0).toDouble(),
      reviewCount: (json['reviewCount'] ?? 0).toInt(),
      services: List<String>.from(json['services'] ?? []),
      distance: (json['distance'] ?? 0.0).toDouble(),
      gigCount: (json['gigCount'] ?? 0).toInt(),
      gigCount7Days: (json['gigCount7Days'] ?? 0).toInt(),
      gigCount30Days: (json['gigCount30Days'] ?? 0).toInt(),
      workspaceAddress: json['workspaceAddress'] ?? '',
      workspaceLat: (json['workspaceLat'] ?? 0.0).toDouble(),
      workspaceLng: (json['workspaceLng'] ?? 0.0).toDouble(),
    );
  }
}

class PaginatedResult {
  final List<ProviderCardData> providers;
  final String? nextCursor;
  final bool hasMore;

  PaginatedResult({
    required this.providers,
    this.nextCursor,
    required this.hasMore,
  });
}
