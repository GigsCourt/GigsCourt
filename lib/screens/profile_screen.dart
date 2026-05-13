import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/image_service.dart';
import '../widgets/profile_sheets.dart';
import 'edit_workspace_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? uid;

  const ProfileScreen({super.key, this.uid});

  bool get isOwnProfile => uid == null;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  final ImageService _imageService = ImageService();

  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  bool _isCollapsed = false;
  String? _error;
  bool _isUploadingPhotos = false;

  String get _currentUid => widget.uid ?? _authService.currentUser?.uid ?? '';
  bool get _isOwnProfile => widget.isOwnProfile;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scrollController.hasClients && _scrollController.offset > 120;
    if (collapsed != _isCollapsed) {
      setState(() => _isCollapsed = collapsed);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await _firestore.collection('profiles').doc(_currentUid).get();
      if (doc.exists && mounted) {
        setState(() {
          _profileData = doc.data();
          _isLoading = false;
        });
        _firestore.collection('profiles').doc(_currentUid).snapshots().listen((snapshot) {
          if (snapshot.exists && mounted) {
            setState(() => _profileData = snapshot.data());
          }
        });
      } else {
        setState(() {
          _error = 'Profile not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final hasScrolled = _isCollapsed && _profileData != null;

    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      leading: _isOwnProfile
          ? null
          : IconButton(
              icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
            ),
      title: hasScrolled
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: _profileData?['photoUrl'] ?? '',
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 24,
                      height: 24,
                      color: Theme.of(context).cardColor,
                      child: Icon(Icons.person, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _profileData?['name'] ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            )
          : null,
      actions: _isOwnProfile
          ? [
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: Icon(Icons.menu, color: Theme.of(context).textTheme.bodyLarge?.color),
              ),
            ]
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildShimmer();
    if (_error != null) return _buildError();
    if (_profileData == null) return _buildError();

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadProfile,
          color: const Color(0xFF1A1F71),
          child: ListView(
            key: const PageStorageKey('profile_list'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatsRow(),
              const SizedBox(height: 24),
              _buildDetailsSection(),
              const SizedBox(height: 24),
              _buildActionButtons(),
              const SizedBox(height: 24),
              _buildWorkPhotos(),
              const SizedBox(height: 40),
            ],
          ),
        ),
        if (_isUploadingPhotos)
          Container(
            color: Colors.black.withAlpha(128),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1A1F71)),
                  SizedBox(height: 16),
                  Text('Uploading photos...', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final gigCount = (_profileData?['gigCount'] ?? 0).toInt();
    final rating = (_profileData?['rating'] ?? 0.0).toDouble();
    final reviewCount = (_profileData?['reviewCount'] ?? 0).toInt();
    final credits = (_profileData?['credits'] ?? 0).toInt();

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: CachedNetworkImage(
            imageUrl: _profileData?['photoUrl'] ?? '',
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: 72,
              height: 72,
              color: Theme.of(context).cardColor,
              child: Icon(Icons.person, size: 36, color: Theme.of(context).textTheme.bodySmall?.color),
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(
                value: gigCount.toString(),
                icon: Icons.work_outline,
                label: 'Gigs',
                onTap: _isOwnProfile ? () => ProfileSheets.gigHistory(context, _currentUid) : null,
              ),
              _buildStat(
                value: rating.toStringAsFixed(1),
                icon: Icons.star_outline,
                label: 'Rating',
                onTap: () => ProfileSheets.reviews(context, _currentUid),
              ),
              _buildStat(
                value: credits.toString(),
                icon: Icons.monetization_on_outlined,
                label: 'Credits',
                onTap: _isOwnProfile ? () => ProfileSheets.credits(context, _currentUid) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat({
    required String value,
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          HapticFeedback.lightImpact();
          onTap();
        }
      },
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 4),
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    final name = _profileData?['name'] ?? '';
    final bio = _profileData?['bio'] ?? '';
    final gigCount30Days = (_profileData?['gigCount30Days'] ?? 0).toInt();
    final gigCount7Days = (_profileData?['gigCount7Days'] ?? 0).toInt();
    final address = _profileData?['workspaceAddress'] ?? '';
    final services = List<String>.from(_profileData?['services'] ?? []);
    final createdAt = _profileData?['createdAt'] as Timestamp?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (gigCount7Days >= 1)
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CAF50),
                  boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withAlpha(77), blurRadius: 4, spreadRadius: 1)],
                ),
              ),
            Flexible(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            ),
          ],
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(bio, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ],
        const SizedBox(height: 8),
        Text('$gigCount30Days gigs this month', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isOwnProfile
                ? () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => EditWorkspaceScreen(
                        currentAddress: address,
                        currentLat: (_profileData?['workspaceLat'] ?? 0.0).toDouble(),
                        currentLng: (_profileData?['workspaceLng'] ?? 0.0).toDouble(),
                      ),
                    ));
                  }
                : null,
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 4),
                Flexible(child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
              ],
            ),
          ),
        ],
        if (services.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isOwnProfile ? () => ProfileSheets.editServices(context, _currentUid, services) : null,
            child: Text(
              services.map((s) => s.replaceAll('-', ' ')).join(', '),
              style: TextStyle(fontSize: 13, color: _isOwnProfile ? const Color(0xFF1A1F71) : const Color(0xFF6B7280)),
            ),
          ),
        ],
        if (createdAt != null) ...[
          const SizedBox(height: 8),
          Text('Joined ${DateFormat('dd/MM/yyyy').format(createdAt.toDate())}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_isOwnProfile) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ProfileSheets.editProfile(context, _currentUid, _profileData!);
              },
              child: const Text('Edit Profile'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ProfileSheets.registerGig(context, _currentUid);
              },
              child: const Text('Register Gig'),
            ),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context, rootNavigator: true).pushNamed('/chat', arguments: _currentUid);
              },
              child: const Text('Message'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                final showPhone = _profileData?['showPhone'] ?? false;
                final phone = _profileData?['phone'] ?? '';
                if (showPhone && phone.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Phone: $phone')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number is private')));
                }
              },
              child: const Text('Contact Now'),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildWorkPhotos() {
    final workPhotos = List<Map<String, dynamic>>.from(
      (_profileData?['workPhotos'] as List<dynamic>?) ?? [],
    );
    final displayPhotos = workPhotos.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isOwnProfile)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _isUploadingPhotos ? null : () => _addWorkPhotos(workPhotos),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Photos'),
            ),
          ),
        const SizedBox(height: 8),
        if (workPhotos.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _isOwnProfile ? 'Add photos so clients can see your work.\nThis helps them trust you.' : 'No work photos yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: displayPhotos.length,
              itemBuilder: (context, index) {
                return _buildWorkPhoto(displayPhotos[index], index, workPhotos);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildWorkPhoto(Map<String, dynamic> photo, int index, List<Map<String, dynamic>> allPhotos) {
    return GestureDetector(
      onTap: () => _viewWorkPhoto(photo),
      onLongPress: _isOwnProfile ? () => _deleteWorkPhoto(photo, allPhotos) : null,
      child: CachedNetworkImage(
        imageUrl: photo['url'] ?? '',
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: Theme.of(context).cardColor),
        errorWidget: (_, __, ___) => Container(
          color: Theme.of(context).cardColor,
          child: Icon(Icons.broken_image, color: Theme.of(context).textTheme.bodySmall?.color),
        ),
      ),
    );
  }

  Future<void> _addWorkPhotos(List<Map<String, dynamic>> existingPhotos) async {
    if (existingPhotos.length >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can add up to 15 photos.')));
      return;
    }

    final remaining = 15 - existingPhotos.length;
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 85, limit: remaining);
    if (pickedFiles == null || pickedFiles.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _isUploadingPhotos = true);

    try {
      final newPhotos = List<Map<String, dynamic>>.from(existingPhotos);

      for (int i = 0; i < pickedFiles.length; i++) {
        final file = File(pickedFiles[i].path);
        final result = await _imageService.uploadToImageKit(file, _currentUid, folder: '/work_photos/$_currentUid');
        newPhotos.add({'url': result.url, 'fileId': result.fileId});
      }

      await _firestore.collection('profiles').doc(_currentUid).update({
        'workPhotos': newPhotos,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      HapticFeedback.heavyImpact();
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhotos = false);
    }
  }

  void _deleteWorkPhoto(Map<String, dynamic> photo, List<Map<String, dynamic>> allPhotos) {
    HapticFeedback.vibrate();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Remove this photo from your work gallery?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();
              try {
                final updatedPhotos = List<Map<String, dynamic>>.from(allPhotos);
                updatedPhotos.removeWhere((p) => p['fileId'] == photo['fileId']);
                await _firestore.collection('profiles').doc(_currentUid).update({
                  'workPhotos': updatedPhotos,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                HapticFeedback.heavyImpact();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _viewWorkPhoto(Map<String, dynamic> photo) {
    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: CachedNetworkImage(
              imageUrl: photo['url'] ?? '',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade700 : Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Container(width: 72, height: 72, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
            const SizedBox(width: 24),
            Expanded(child: Container(height: 14, color: Colors.grey)),
          ]),
          const SizedBox(height: 24),
          Container(height: 14, width: 200, color: Colors.grey),
          const SizedBox(height: 8),
          Container(height: 14, color: Colors.grey),
          const SizedBox(height: 8),
          Container(height: 100, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).textTheme.bodySmall?.color),
          const SizedBox(height: 16),
          Text(_error ?? 'Something went wrong', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
        ],
      ),
    );
  }
}
