import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_service.dart';

class ProfileSetupStep1 extends StatefulWidget {
  final String? initialName;
  final String? initialPhone;
  final String? initialBio;
  final File? initialPhoto;
  final Function(String name, String phone, String bio, File? photo) onChanged;

  const ProfileSetupStep1({
    super.key,
    this.initialName,
    this.initialPhone,
    this.initialBio,
    this.initialPhoto,
    required this.onChanged,
  });

  @override
  State<ProfileSetupStep1> createState() => _ProfileSetupStep1State();
}

class _ProfileSetupStep1State extends State<ProfileSetupStep1> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  File? _photo;
  final ImageService _imageService = ImageService();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    _phoneController.text = widget.initialPhone ?? '';
    _bioController.text = widget.initialBio ?? '';
    _photo = widget.initialPhoto;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _notifyParent() {
    widget.onChanged(
      _nameController.text.trim(),
      _phoneController.text.trim(),
      _bioController.text.trim(),
      _photo,
    );
  }

  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(ctx);
                final photo = await _imageService.takePhoto();
                if (photo != null) {
                  setState(() => _photo = photo);
                  _notifyParent();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                final photo = await _imageService.pickFromGallery();
                if (photo != null) {
                  setState(() => _photo = photo);
                  _notifyParent();
                }
              },
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  setState(() => _photo = null);
                  _notifyParent();
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  bool validate() {
    return _formKey.currentState?.validate() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Progress hint
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete your profile to be discoverable to clients near you',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Photo picker
            GestureDetector(
              onTap: _showPhotoSheet,
              child: Stack(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).cardColor,
                      border: Border.all(
                        color: _photo != null ? const Color(0xFF4CAF50) : const Color(0xFF1A1F71),
                        width: 2,
                      ),
                      image: _photo != null
                          ? DecorationImage(
                              image: FileImage(_photo!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _photo == null
                        ? const Icon(
                            Icons.person,
                            size: 40,
                            color: Color(0xFF6B7280),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1A1F71),
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a profile photo',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 24),
            // Name field
            TextFormField(
              controller: _nameController,
              onChanged: (_) => _notifyParent(),
              decoration: const InputDecoration(
                labelText: 'Full Name / Business Name *',
                hintText: 'e.g. John Doe Electrical Services',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required to appear in search results';
                }
                return null;
              },
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Clients will see this name when they find your services',
                style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
            const SizedBox(height: 20),
            // Phone field
            TextFormField(
              controller: _phoneController,
              onChanged: (_) => _notifyParent(),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number (optional)',
                hintText: 'e.g. +234 800 000 0000',
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Helps clients reach you faster — you can hide this later',
                style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
            const SizedBox(height: 20),
            // Bio field
            TextFormField(
              controller: _bioController,
              onChanged: (_) => _notifyParent(),
              maxLines: null,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Bio (optional)',
                hintText: 'Tell clients about your experience, specialties, and what makes you great at your work...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'A good bio builds trust and helps you stand out',
                style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
