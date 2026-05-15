import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  // Get GPS position — always fetches fresh
  Future<LatLng> getLocation() async {
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

    return LatLng(position.latitude, position.longitude);
  }

  // Stream location changes for 100m detection
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
