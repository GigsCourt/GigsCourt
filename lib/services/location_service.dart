import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static const double _refreshThresholdMeters = 100.0;

  LatLng? _cachedLocation;
  bool _isFetching = false;

  // Get GPS position — returns cached if available, otherwise fetches fresh
  Future<LatLng> getCurrentLocation() async {
    if (_cachedLocation != null) return _cachedLocation!;

    return refreshLocation();
  }

  // Force a fresh GPS fetch
  Future<LatLng> refreshLocation() async {
    if (_isFetching) {
      // If already fetching, wait briefly for it to complete
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_cachedLocation != null) return _cachedLocation!;
      }
      throw LocationPermissionException();
    }

    _isFetching = true;

    try {
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _cachedLocation = LatLng(position.latitude, position.longitude);
      return _cachedLocation!;
    } finally {
      _isFetching = false;
    }
  }

  // Stream location changes for 100m detection
  Stream<LatLng> get locationStream {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      ),
    ).map((position) {
      final newLocation = LatLng(position.latitude, position.longitude);

      if (_cachedLocation != null) {
        final distance = Geolocator.distanceBetween(
          _cachedLocation!.latitude,
          _cachedLocation!.longitude,
          newLocation.latitude,
          newLocation.longitude,
        );

        if (distance >= _refreshThresholdMeters) {
          _cachedLocation = newLocation;
        }
      } else {
        _cachedLocation = newLocation;
      }

      return newLocation;
    });
  }
}

class LocationPermissionException implements Exception {
  @override
  String toString() => 'Location permission denied';
}
