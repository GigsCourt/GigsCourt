import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

class HomeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _trendingCacheKey = 'home_trending_cache';
  static const String _nearbyCacheKey = 'home_nearby_cache';
  static const int _pageSize = 10;

  // Get cached trending providers
  Future<List<ProviderCardData>> getCachedTrending() async {
    return _getCached(_trendingCacheKey);
  }

  // Get cached nearby providers
  Future<List<ProviderCardData>> getCachedNearby() async {
    return _getCached(_nearbyCacheKey);
  }

  // Fetch Trending providers (velocity-based)
  Future<PaginatedResult> fetchTrending({
    required LatLng userLocation,
    String? cursor,
  }) async {
    return _fetchProviders(
      userLocation: userLocation,
      cursor: cursor,
      cacheKey: _trendingCacheKey,
      sortForTrending: true,
    );
  }

  // Fetch Nearby providers (distance-based)
  Future<PaginatedResult> fetchNearby({
    required LatLng userLocation,
    String? cursor,
  }) async {
    return _fetchProviders(
      userLocation: userLocation,
      cursor: cursor,
      cacheKey: _nearbyCacheKey,
      sortForTrending: false,
    );
  }

  // Core fetch logic
  Future<PaginatedResult> _fetchProviders({
    required LatLng userLocation,
    String? cursor,
    required String cacheKey,
    required bool sortForTrending,
  }) async {
    // 1. Call Supabase RPC for nearby profile IDs
    final supabaseResult = await _supabase.rpc('get_nearby_profiles', params: {
      'user_lat': userLocation.latitude,
      'user_lng': userLocation.longitude,
      'p_cursor': cursor,
      'p_limit': _pageSize,
    });

    if (supabaseResult == null || (supabaseResult as List).isEmpty) {
      return PaginatedResult(providers: [], nextCursor: null, hasMore: false);
    }

    final List<dynamic> rows = supabaseResult;
    final uids = rows.map((r) => r['id'] as String).toList();
    final distances = Map<String, double>.fromEntries(
      rows.map((r) => MapEntry(r['id'] as String, (r['distance_meters'] as num).toDouble())),
    );

    // Determine if there are more pages
    final hasMore = rows.length > _pageSize;
    final nextCursor = hasMore ? uids[_pageSize - 1] : null;
    final fetchUids = hasMore ? uids.sublist(0, _pageSize) : uids;

    // 2. Batch read from Firestore
    final firestoreData = await _batchReadProfiles(fetchUids);

    // 3. Merge and sort
    final providers = _mergeAndSort(firestoreData, distances, userLocation, sortForTrending);

    // 4. Cache if first page
    if (cursor == null && providers.isNotEmpty) {
      _cacheProviders(cacheKey, providers);
    }

    return PaginatedResult(
      providers: providers,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  // Batch read profiles from Firestore
  Future<Map<String, Map<String, dynamic>>> _batchReadProfiles(List<String> uids) async {
    final result = <String, Map<String, dynamic>>{};

    // Firestore batch reads in chunks of 10
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

  // Merge Supabase distances with Firestore data and sort
  List<ProviderCardData> _mergeAndSort(
    Map<String, Map<String, dynamic>> firestoreData,
    Map<String, double> distances,
    LatLng userLocation,
    bool sortForTrending,
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

    if (sortForTrending) {
      // Filter: must have ≥1 gig in 7 days AND ≥1 review
      providers.removeWhere((p) => p.gigCount7Days < 1 || p.reviewCount < 1);
      // Sort: velocity DESC → distance ASC → rating DESC → gigs DESC
      providers.sort((a, b) {
        final velocityCompare = b.gigCount7Days.compareTo(a.gigCount7Days);
        if (velocityCompare != 0) return velocityCompare;
        final distanceCompare = a.distance.compareTo(b.distance);
        if (distanceCompare != 0) return distanceCompare;
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.gigCount.compareTo(a.gigCount);
      });
    } else {
      // Nearby: distance ASC → activity badge → rating DESC → gigs DESC
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

  // Cache providers to SharedPreferences
  Future<void> _cacheProviders(String key, List<ProviderCardData> providers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = providers.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(key, jsonList);
  }

  // Get cached providers from SharedPreferences
  Future<List<ProviderCardData>> _getCached(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(key);
    if (jsonList == null || jsonList.isEmpty) return [];
    return jsonList
        .map((j) => ProviderCardData.fromJson(jsonDecode(j)))
        .toList();
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
