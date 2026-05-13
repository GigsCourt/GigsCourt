import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_service.dart';

class ProfileSheets {
  // Edit Profile bottom sheet
  static void editProfile(BuildContext context, String uid, Map<String, dynamic> data) {
    final nameController = TextEditingController(text: data['name'] ?? '');
    final phoneController = TextEditingController(text: data['phone'] ?? '');
    final bioController = TextEditingController(text: data['bio'] ?? '');
    final formKey = GlobalKey<FormState>();
    final ImageService _imageService = ImageService();
    String? photoUrl = data['photoUrl'];
    String? photoFileId = data['photoFileId'];
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B7280).withAlpha(77),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(ctx).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Photo picker
                      Center(
                        child: GestureDetector(
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final file = await _imageService.pickFromGallery();
                            if (file != null) {
                              try {
                                final result = await _imageService.uploadToImageKit(file, uid);
                                setSheetState(() {
                                  photoUrl = result.url;
                                  photoFileId = result.fileId;
                                });
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Photo upload failed: $e')),
                                  );
                                }
                              }
                            }
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(ctx).cardColor,
                              border: Border.all(
                                color: photoUrl != null ? const Color(0xFF4CAF50) : const Color(0xFF1A1F71),
                                width: 2,
                              ),
                              image: photoUrl != null && photoUrl!.isNotEmpty
                                  ? DecorationImage(image: NetworkImage(photoUrl!), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: photoUrl == null || photoUrl!.isEmpty
                                ? const Icon(Icons.camera_alt, size: 28, color: Color(0xFF6B7280))
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Full Name / Business Name'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number (optional)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: bioController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                HapticFeedback.mediumImpact();
                                setSheetState(() => isSaving = true);
                                try {
                                  final updates = <String, dynamic>{
                                    'name': nameController.text.trim(),
                                    'phone': phoneController.text.trim(),
                                    'bio': bioController.text.trim(),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  };
                                  if (photoUrl != null) {
                                    updates['photoUrl'] = photoUrl;
                                    updates['photoFileId'] = photoFileId;
                                  }
                                  await FirebaseFirestore.instance
                                      .collection('profiles')
                                      .doc(uid)
                                      .update(updates);
                                  HapticFeedback.heavyImpact();
                                  Navigator.pop(ctx);
                                } catch (e) {
                                  HapticFeedback.vibrate();
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                                setSheetState(() => isSaving = false);
                              },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Edit Services bottom sheet
  static void editServices(BuildContext context, String uid, List<String> currentServices) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _EditServicesSheet(uid: uid, currentServices: currentServices);
      },
    );
  }

  // Gig History bottom sheet (two tabs)
  static void gigHistory(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: SafeArea(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Gig History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  TabBar(
                    labelColor: const Color(0xFF1A1F71),
                    unselectedLabelColor: const Color(0xFF6B7280),
                    indicatorColor: const Color(0xFF1A1F71),
                    tabs: const [
                      Tab(text: 'As Provider'),
                      Tab(text: 'As Client'),
                    ],
                  ),
                  const Expanded(
                    child: TabBarView(
                      children: [
                        Center(child: Text('No gigs as provider yet', style: TextStyle(color: Color(0xFF6B7280)))),
                        Center(child: Text('No gigs as client yet', style: TextStyle(color: Color(0xFF6B7280)))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Reviews bottom sheet
  static void reviews(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Reviews',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'No reviews yet',
                      style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Credits bottom sheet
  static void credits(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280).withAlpha(77),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Credits',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Credit packages coming soon',
                  style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  // Register Gig chat list bottom sheet
  static void registerGig(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Register a Gig',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Select a recent chat to register a gig',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Text(
                      'No recent chats',
                      style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditServicesSheet extends StatefulWidget {
  final String uid;
  final List<String> currentServices;

  const _EditServicesSheet({required this.uid, required this.currentServices});

  @override
  State<_EditServicesSheet> createState() => _EditServicesSheetState();
}

class _EditServicesSheetState extends State<_EditServicesSheet> {
  late List<String> _selectedServices;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedServices = List<String>.from(widget.currentServices);
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('profiles').doc(widget.uid).update({
        'services': _selectedServices,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Services',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
            // Selected chips
            if (_selectedServices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedServices.map((slug) {
                    return Chip(
                      label: Text(slug.replaceAll('-', ' '), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: const Color(0xFF1A1F71),
                      deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
                      onDeleted: () => setState(() => _selectedServices.remove(slug)),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Text(
                  'Tap services on your profile to remove them.\nFull service editor coming soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
