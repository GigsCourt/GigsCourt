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
  LatLng _center = const LatLng(0, 0);
  bool _isLoading = true;
  String? _errorMessage;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.initialAddress ?? '';
    if (widget.initialLocation != null) {
      _center = widget.initialLocation!;
      _isLoading = false;
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
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Location access denied. Please enable location in Settings.';
            });
          }
          return;
        }
      }

      if (hasPermission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Location access denied. Please enable location in Settings.';
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _center = LatLng(position.latitude, position.longitude);
          _isLoading = false;
          _errorMessage = null;
        });
        _moveMapToCenter();
        _reverseGeocode(_center);
        _notifyParent();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not get your location. Tap to retry.';
        });
      }
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
    } catch (_) {}
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
      final newCenter = _mapController.camera.center;
      if (newCenter != _center) {
        _center = newCenter;
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
        if (_errorMessage != null)
          GestureDetector(
            onTap: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _getCurrentLocation();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.orange.withAlpha(26),
              child: Row(
                children: [
                  const Icon(Icons.location_off, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                  const Text('Retry', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        Expanded(
          child: _isLoading
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
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).scaffoldBackgroundColor.withAlpha(240),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Describe your workspace location',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Drag the map to place the pin, then add details.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _addressController,
                                onChanged: (_) => _notifyParent(),
                                maxLines: 2,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Address or nearby landmark...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
