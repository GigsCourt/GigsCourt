import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import '../services/image_service.dart';
import '../services/push_service.dart';
import 'profile_setup_step1.dart';
import 'profile_setup_step2.dart';
import 'profile_setup_step3.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();
  final ImageService _imageService = ImageService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _currentStep = 0;
  bool _isSaving = false;

  String _name = '';
  String _phone = '';
  String _bio = '';
  File? _photo;

  List<String> _selectedServices = [];

  LatLng _workspaceLocation = const LatLng(9.082, 8.6753);
  String _workspaceAddress = '';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = step);
  }

  Future<void> _updateServiceCounts(List<String> services) async {
    for (final slug in services) {
      await _firestore.collection('metadata').doc('service_counts').set({
        slug: FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _completeSetup() async {
    final user = _authService.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      String? photoUrl;
      String? photoFileId;

      if (_photo != null) {
        final result = await _imageService.uploadToImageKit(_photo!, user.uid);
        photoUrl = result.url;
        photoFileId = result.fileId;
      }

      await _supabase.from('profiles').upsert({
        'id': user.uid,
        'workspace_location':
            'POINT(${_workspaceLocation.longitude} ${_workspaceLocation.latitude})',
        'workspace_address': _workspaceAddress,
        'services': _selectedServices,
        'updated_at': DateTime.now().toIso8601String(),
      });

      try {
        await _firestore.collection('profiles').doc(user.uid).set({
          'name': _name,
          'phone': _phone,
          'bio': _bio,
          'photoUrl': photoUrl ?? '',
          'photoFileId': photoFileId ?? '',
          'services': _selectedServices,
          'workspaceAddress': _workspaceAddress,
          'workspaceLat': _workspaceLocation.latitude,
          'workspaceLng': _workspaceLocation.longitude,
          'rating': 0.0,
          'reviewCount': 0,
          'gigCount': 0,
          'gigCount7Days': 0,
          'gigCount30Days': 0,
          'credits': 5,
          'showPhone': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (firestoreError) {
        await _supabase.from('profiles').delete().eq('id', user.uid);
        rethrow;
      }

      // Update service counts for search popularity
      if (_selectedServices.isNotEmpty) {
        await _updateServiceCounts(_selectedServices);
      }

      PushService().sendWelcome(user.uid);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    GestureDetector(
                      onTap: () => _goToStep(_currentStep - 1),
                      child: const Icon(Icons.arrow_back),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Text(
                    'Step ${_currentStep + 1} of 3',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                  ),
                  const Spacer(),
                  Text(
                    '${((_currentStep + 1) / 3 * 100).round()}%',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(3, (index) {
                  final isActive = index <= _currentStep;
                  final isCurrent = index == _currentStep;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(right: 8),
                    width: isCurrent ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF1A1F71) : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentStep = page),
                children: [
                  ProfileSetupStep1(
                    initialName: _name,
                    initialPhone: _phone,
                    initialBio: _bio,
                    initialPhoto: _photo,
                    onChanged: (name, phone, bio, photo) {
                      _name = name;
                      _phone = phone;
                      _bio = bio;
                      _photo = photo;
                    },
                  ),
                  ProfileSetupStep2(
                    initialServices: _selectedServices,
                    onChanged: (services) {
                      _selectedServices = services;
                    },
                  ),
                  ProfileSetupStep3(
                    initialLocation: _workspaceLocation,
                    initialAddress: _workspaceAddress,
                    onChanged: (location, address) {
                      _workspaceLocation = location;
                      _workspaceAddress = address;
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : _currentStep == 2
                          ? _completeSetup
                          : () {
                              if (_currentStep == 0 && _name.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter your name to continue')),
                                );
                                return;
                              }
                              _goToStep(_currentStep + 1);
                            },
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _currentStep == 2 ? 'Complete Setup' : 'Next',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
