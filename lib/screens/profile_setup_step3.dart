import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class ProfileSetupStep3 extends StatefulWidget {
  final LatLng? initialLocation;
  final String? initialAddress;
  final Function(LatLng location, String address) onChanged;

  const ProfileSetupStep3({
    super.key,
    this.initialLocation,
    this.initialAddress,
    required this.onChanged,
  });

  @override
  State<ProfileSetupStep3> createState() => _ProfileSetupStep3State();
}

class _ProfileSetupStep3State extends State<ProfileSetupStep3> {
  final MapController _mapController = MapController();
  final TextEditingController _addressController = TextEditingController();
  LatLng _center = const LatLng(9.082, 8.6753); // Lagos fallback
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.initialAddress ?? '';
    if (widget.initialLocation != null) {
      _center = widget.initialLocation!;
      _isLoadingLocation = false;
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final hasPermission = await Geolocator.checkPermission();
      if (hasPermission == LocationPermission.denied) {
        final permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          setState(() => _isLoadingLocation = false);
          _notifyParent();
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _center = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        _reverseGeocode(_center);
        _notifyParent();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        _notifyParent();
      }
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isNotEmpty && _addressController.text.isEmpty) {
        final p = placemarks.first;
        final address = '${p.street ?? ''}, ${p.locality ?? ''}, ${p.administrativeArea ?? ''}'
            .replaceAll(RegExp(r'^, |, $|,,+'), '')
            .trim();
        if (address.isNotEmpty) {
          _addressController.text = address;
          _notifyParent();
        }
      }
    } catch (e) {
      // Silently fail — user can type address manually
    }
  }

  void _notifyParent() {
    widget.onChanged(_center, _addressController.text);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLocation) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Getting your location...',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Map
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: 15.0,
                  onMapEvent: (event) {
                    // Ignore fling events, only capture drag end
                  },
                  onMapReady: () {
                    // Map is centered on user location
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gigscourt.app',
                  ),
                ],
              ),
              // Fixed centered pin
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 44,
                      color: Color(0xFF1A1F71),
                    ),
                    SizedBox(height: 44), // Pin tip compensation
                  ],
                ),
              ),
            ],
          ),
        ),
        // Address field
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Workspace Address',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 4),
              Text(
                'Drag the map to center the pin on your workspace',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                onChanged: (_) => _notifyParent(),
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Describe your workspace location...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This helps clients find you nearby. You can edit this text.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
