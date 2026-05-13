import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditWorkspaceScreen extends StatefulWidget {
  final String currentAddress;
  final double currentLat;
  final double currentLng;

  const EditWorkspaceScreen({
    super.key,
    required this.currentAddress,
    required this.currentLat,
    required this.currentLng,
  });

  @override
  State<EditWorkspaceScreen> createState() => _EditWorkspaceScreenState();
}

class _EditWorkspaceScreenState extends State<EditWorkspaceScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _addressController = TextEditingController();
  late LatLng _center;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _center = LatLng(widget.currentLat, widget.currentLng);
    _addressController.text = widget.currentAddress;
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
      _center = _mapController.camera.center;
    }
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('profiles').doc(user.uid).update({
        'workspaceAddress': _addressController.text.trim(),
        'workspaceLat': _center.latitude,
        'workspaceLng': _center.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workspace updated')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.close, color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Edit Workspace',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Map — takes up most of the screen
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 16.0,
                    onMapEvent: _onMapEvent,
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              controller: _addressController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Describe your workspace location...',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
