import 'dart:async';
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
  late LatLng _center;
  bool _isLoadingLocation = true;
  String? _locationBannerMessage;
  bool _isBannerWarning = false;
  bool _userHasDraggedMap = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;
  Timer? _retryTimer;
  bool _permissionDeniedPermanently = false;
  bool _mapReady = false;
  static const LatLng _lagosFallback = LatLng(9.082, 8.6753);

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.initialAddress ?? '';
    _center = widget.initialLocation ?? _lagosFallback;
    if (widget.initialLocation != null) {
      _isLoadingLocation = false;
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    if (_userHasDraggedMap) return;

    try {
      final hasPermission = await Geolocator.checkPermission();

      if (hasPermission == LocationPermission.denied) {
        final permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionDenied();
          return;
        }
        if (permission == LocationPermission.deniedForever) {
          _showPermissionPermanentlyDenied();
          return;
        }
      }

      if (hasPermission == LocationPermission.deniedForever) {
        _showPermissionPermanentlyDenied();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (mounted && !_userHasDraggedMap) {
        _retryTimer?.cancel();
        setState(() {
          _center = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
          _locationBannerMessage = null;
        });
        _moveMapToCenter();
        _reverseGeocode(_center);
        _notifyParent();
      }
    } on TimeoutException {
      _handleLocationFailure('Location request timed out. Retrying...');
    } catch (e) {
      _handleLocationFailure('Couldn\'t get your location. Retrying...');
    }
  }

  void _moveMapToCenter() {
    if (_mapReady) {
      _mapController.move(_center, 15.0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) {
          _mapController.move(_center, 15.0);
        }
      });
    }
  }

  void _showPermissionDenied() {
    setState(() {
      _isLoadingLocation = false;
      _locationBannerMessage = 'Location access was denied. Showing default area. Drag the map to set your workspace.';
      _isBannerWarning = true;
      _permissionDeniedPermanently = false;
    });
  }

  void _showPermissionPermanentlyDenied() {
    setState(() {
      _isLoadingLocation = false;
      _locationBannerMessage = 'Location access was denied. Showing default area. Drag the map to set your workspace.';
      _isBannerWarning = true;
      _permissionDeniedPermanently = true;
    });
  }

  void _handleLocationFailure(String message) {
    if (_permissionDeniedPermanently) return;

    if (_retryCount < _maxRetries && !_userHasDraggedMap) {
      setState(() {
        _retryCount++;
        _isLoadingLocation = false;
        _locationBannerMessage = '$message (Attempt ${_retryCount}/$_maxRetries)';
        _isBannerWarning = true;
      });
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _getCurrentLocation();
      });
    } else {
      setState(() {
        _isLoadingLocation = false;
        _locationBannerMessage = 'Location unavailable. Showing default area. Drag the map to set your workspace.';
        _isBannerWarning = true;
      });
    }
  }

  void _retryManually() {
    _retryCount = 0;
    _userHasDraggedMap = false;
    _permissionDeniedPermanently = false;
    setState(() {
      _isLoadingLocation = true;
      _locationBannerMessage = null;
    });
    _getCurrentLocation();
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final placemarks = await placemarkFromCoordinates(point.latitude, point.longitude);
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
    } catch (e) {}
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
      final newCenter = _mapController.camera.center;
      if (newCenter != _center) {
        _center = newCenter;
        if (!_userHasDraggedMap) {
          setState(() {
            _userHasDraggedMap = true;
            _locationBannerMessage = null;
            _retryTimer?.cancel();
          });
        }
        _notifyParent();
      }
    }
  }

  void _notifyParent() {
    widget.onChanged(_center, _addressController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Location banner
        if (_locationBannerMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.withAlpha(26),
            child: Row(
              children: [
                const Icon(Icons.location_off, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationBannerMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
                if (_isBannerWarning && !_permissionDeniedPermanently)
                  TextButton(
                    onPressed: _retryManually,
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        // Map — only renders after location is resolved
        Expanded(
          flex: 3,
          child: _isLoadingLocation
              ? Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const Center(
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
                  ),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _center,
                        initialZoom: 15.0,
                        onMapEvent: _onMapEvent,
                        onMapReady: () {
                          setState(() => _mapReady = true);
                          _moveMapToCenter();
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.gigscourt.app',
                        ),
                      ],
                    ),
                    const IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on, size: 44, color: Color(0xFF1A1F71)),
                            SizedBox(height: 44),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        // Address field
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set Your Workspace',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Drag the map to center the pin on your workspace.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  onChanged: (_) => _notifyParent(),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Your workspace address or description...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This helps clients find you nearby. You can describe your location in your own words.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
