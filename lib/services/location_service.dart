import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static const String _lastLatKey = 'last_location_lat';
  static const String _lastLngKey = 'last_location_lng';
  static const double _refreshThresholdMeters = 100.0;

  // Get current GPS position
  Future<LatLng> getCurrentLocation() async {
    final hasPermission = await Geolocator.checkPermission();

    if (hasPermission == LocationPermission.denied) {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw LocationPermissionException();
      }
    }

    if (hasPermission == LocationPermission.deniedForever) {
      throw LocationPermissionException();
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 10));

    return LatLng(position.latitude, position.longitude);
  }

  // Check if user has moved 100+ meters since last fetch
  Future<bool> shouldRefresh(LatLng currentLocation) async {
    final prefs = await SharedPreferences.getInstance();
    final lastLat = prefs.getDouble(_lastLatKey);
    final lastLng = prefs.getDouble(_lastLngKey);

    if (lastLat == null || lastLng == null) return true;

    final distance = Geolocator.distanceBetween(
      lastLat,
      lastLng,
      currentLocation.latitude,
      currentLocation.longitude,
    );

    return distance >= _refreshThresholdMeters;
  }

  // Save current location as last fetch point
  Future<void> updateLastFetch(LatLng location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lastLatKey, location.latitude);
    await prefs.setDouble(_lastLngKey, location.longitude);
  }

  // Stream location changes for 100m detection while app is open
  Stream<LatLng> get locationStream {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      ),
    ).map((position) => LatLng(position.latitude, position.longitude));
  }
}

class LocationPermissionException implements Exception {
  @override
  String toString() => 'Location permission denied';
}
