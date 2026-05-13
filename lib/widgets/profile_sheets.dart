import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
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
                  left: 24, right: 24, top: 24,
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
                      Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyLarge?.color)),
                      const SizedBox(height: 20),
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
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
                                }
                              }
                            }
                          },
                          child: Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(ctx).cardColor,
                              border: Border.all(color: photoUrl != null ? const Color(0xFF4CAF50) : const Color(0xFF1A1F71), width: 2),
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
                      TextFormField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number (optional)')),
                      const SizedBox(height: 12),
                      TextFormField(controller: bioController, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', alignLabelWithHint: true)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isSaving ? null : () async {
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
                            await FirebaseFirestore.instance.collection('profiles').doc(uid).update(updates);
                            HapticFeedback.heavyImpact();
                            Navigator.pop(ctx);
                          } catch (e) {
                            HapticFeedback.vibrate();
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EditServicesSheet(uid: uid, currentServices: currentServices),
    );
  }

  // Gig History bottom sheet (two tabs, wired to Firestore)
  static void gigHistory(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: SafeArea(child: _GigHistoryContent(uid: uid)),
      ),
    );
  }

  // Reviews bottom sheet (wired to Firestore)
  static void reviews(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: SafeArea(child: _ReviewsContent(uid: uid)),
      ),
    );
  }

  // Credits bottom sheet (shows balance)
  static void credits(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CreditsContent(uid: uid),
    );
  }

  // Register Gig chat list bottom sheet
  static void registerGig(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: SafeArea(child: _RegisterGigContent(uid: uid)),
      ),
    );
  }
}

// -- Edit Services Sheet --
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Edit Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
              ),
            ],
          ),
        ),
        if (_selectedServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8, runSpacing: 8,
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
            child: Text('Tap services on your profile to remove them.\nFull service editor coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

// -- Gig History Content --
class _GigHistoryContent extends StatefulWidget {
  final String uid;
  const _GigHistoryContent({required this.uid});
  @override
  State<_GigHistoryContent> createState() => _GigHistoryContentState();
}

class _GigHistoryContentState extends State<_GigHistoryContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Gig History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        ),
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1A1F71),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF1A1F71),
          tabs: const [Tab(text: 'As Provider'), Tab(text: 'As Client')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GigList(uid: widget.uid, role: 'provider'),
              _GigList(uid: widget.uid, role: 'client'),
            ],
          ),
        ),
      ],
    );
  }
}

class _GigList extends StatefulWidget {
  final String uid;
  final String role;
  const _GigList({required this.uid, required this.role});
  @override
  State<_GigList> createState() => _GigListState();
}

class _GigListState extends State<_GigList> {
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _gigs = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _fetchGigs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) _fetchMore();
  }

  Future<void> _fetchGigs() async {
    try {
      final field = widget.role == 'provider' ? 'providerId' : 'clientId';
      final snapshot = await _firestore.collection('gigs').where(field, isEqualTo: widget.uid).orderBy('createdAt', descending: true).limit(_pageSize).get();
      if (mounted) {
        setState(() {
          _gigs = snapshot.docs.map((d) => d.data()).toList();
          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final field = widget.role == 'provider' ? 'providerId' : 'clientId';
      final snapshot = await _firestore.collection('gigs').where(field, isEqualTo: widget.uid).orderBy('createdAt', descending: true).startAfterDocument(_lastDoc!).limit(_pageSize).get();
      if (mounted) {
        setState(() {
          _gigs.addAll(snapshot.docs.map((d) => d.data()));
          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_gigs.isEmpty) return Center(child: Text('No gigs yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)));
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _gigs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _gigs.length) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
        final g = _gigs[index];
        final status = g['status'] ?? 'pending';
        final service = g['service'] ?? '';
        final createdAt = g['createdAt'] as Timestamp?;
        return Card(
          color: Theme.of(context).cardColor,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(service.replaceAll('-', ' '), style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
            subtitle: createdAt != null ? Text(DateFormat('dd MMM yyyy').format(createdAt.toDate()), style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))) : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'completed' ? const Color(0xFF4CAF50).withAlpha(26) : status == 'cancelled' ? Colors.red.withAlpha(26) : Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status == 'completed' ? 'Completed' : status == 'cancelled' ? 'Cancelled' : 'Pending',
                style: TextStyle(fontSize: 11, color: status == 'completed' ? const Color(0xFF4CAF50) : status == 'cancelled' ? Colors.red : Colors.orange),
              ),
            ),
          ),
        );
      },
    );
  }
}

// -- Reviews Content --
class _ReviewsContent extends StatefulWidget {
  final String uid;
  const _ReviewsContent({required this.uid});
  @override
  State<_ReviewsContent> createState() => _ReviewsContentState();
}

class _ReviewsContentState extends State<_ReviewsContent> {
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _reviews = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) _fetchMore();
  }

  Future<void> _fetchReviews() async {
    try {
      final snapshot = await _firestore.collection('reviews').where('providerId', isEqualTo: widget.uid).orderBy('createdAt', descending: true).limit(_pageSize).get();
      if (mounted) {
        setState(() {
          _reviews = snapshot.docs.map((d) => d.data()).toList();
          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final snapshot = await _firestore.collection('reviews').where('providerId', isEqualTo: widget.uid).orderBy('createdAt', descending: true).startAfterDocument(_lastDoc!).limit(_pageSize).get();
      if (mounted) {
        setState(() {
          _reviews.addAll(snapshot.docs.map((d) => d.data()));
          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_reviews.isEmpty) return Center(child: Text('No reviews yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _reviews.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _reviews.length) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
              final r = _reviews[index];
              final rating = (r['rating'] ?? 0).toInt();
              final text = r['text'] ?? '';
              final createdAt = r['createdAt'] as Timestamp?;
              return Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ...List.generate(5, (i) => Icon(Icons.star, size: 16, color: i < rating ? Colors.amber : const Color(0xFF6B7280).withAlpha(77))),
                          const Spacer(),
                          if (createdAt != null) Text(DateFormat('dd MMM yyyy').format(createdAt.toDate()), style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ],
                      ),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(text, style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color)),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -- Credits Content --
class _CreditsContent extends StatefulWidget {
  final String uid;
  const _CreditsContent({required this.uid});
  @override
  State<_CreditsContent> createState() => _CreditsContentState();
}

class _CreditsContentState extends State<_CreditsContent> {
  int _credits = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('profiles').doc(widget.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _credits = (doc.data()?['credits'] ?? 0).toInt();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF6B7280).withAlpha(77), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Credits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 16),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Text('$_credits credits remaining', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                    const SizedBox(height: 8),
                    const Text('Credits allow clients to rate and review your work.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // The caller (settings or profile) handles navigation to buy credits
                      },
                      child: const Text('Buy Credits'),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

// -- Register Gig Content --
class _RegisterGigContent extends StatefulWidget {
  final String uid;
  const _RegisterGigContent({required this.uid});
  @override
  State<_RegisterGigContent> createState() => _RegisterGigContentState();
}

class _RegisterGigContentState extends State<_RegisterGigContent> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecentChats();
  }

  Future<void> _fetchRecentChats() async {
    try {
      final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
      final snapshot = await _firestore
          .collection('chats')
          .where('participants', arrayContains: widget.uid)
          .where('lastMessageTime', isGreaterThanOrEqualTo: Timestamp.fromDate(twoWeeksAgo))
          .orderBy('lastMessageTime', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _chats = snapshot.docs.map((d) => d.data()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Register a Gig', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Select a recent chat to register a gig', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _chats.isEmpty
                  ? Center(child: Text('No recent chats', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _chats.length,
                      itemBuilder: (context, index) {
                        final chat = _chats[index];
                        final participants = List<String>.from(chat['participants'] ?? []);
                        final otherUid = participants.firstWhere((p) => p != widget.uid, orElse: () => '');
                        return ListTile(
                          title: Text('Chat with user', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                          subtitle: Text(otherUid, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                          trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                            Navigator.of(context, rootNavigator: true).pushNamed('/chat', arguments: otherUid);
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
