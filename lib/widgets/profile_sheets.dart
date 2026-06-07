import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/image_service.dart';
import '../screens/edit_workspace_screen.dart';
import '../utils/error_handler.dart';

class ServiceItem {
  final String name;
  final int price;
  final String currency;

  ServiceItem({required this.name, required this.price, this.currency = 'NGN'});

  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'currency': currency};

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    return ServiceItem(
      name: json['name'] ?? '',
      price: (json['price'] ?? 0).toInt(),
      currency: json['currency'] ?? 'NGN',
    );
  }
}

class ProfileSheets {
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
      context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF6B7280).withAlpha(77), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyLarge?.color)),
            const SizedBox(height: 20),
            Center(child: GestureDetector(onTap: () async {
              HapticFeedback.lightImpact();
              final file = await _imageService.pickFromGallery();
              if (file != null) {
                try {
                  final result = await _imageService.uploadToImageKit(file, uid);
                  setSheetState(() { photoUrl = result.url; photoFileId = result.fileId; });
                } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Photo upload failed: $e'))); }
              }
            }, child: Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(ctx).cardColor, border: Border.all(color: photoUrl != null ? const Color(0xFF4CAF50) : const Color(0xFF1A1F71), width: 2), image: photoUrl != null && photoUrl!.isNotEmpty ? DecorationImage(image: NetworkImage(photoUrl!), fit: BoxFit.cover) : null), child: photoUrl == null || photoUrl!.isEmpty ? const Icon(Icons.camera_alt, size: 28, color: Color(0xFF6B7280)) : null))),
            const SizedBox(height: 16),
            TextFormField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name / Business Name'), validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null),
            const SizedBox(height: 12),
            TextFormField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number (optional)')),
            const SizedBox(height: 12),
            TextFormField(controller: bioController, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(ctx); Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => EditWorkspaceScreen(currentAddress: data['workspaceAddress'] ?? '', currentLat: (data['workspaceLat'] ?? 0.0).toDouble(), currentLng: (data['workspaceLng'] ?? 0.0).toDouble()))); },
              icon: const Icon(Icons.location_on_outlined, size: 14), label: const Text('Workspace Address', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
            )),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(ctx); final categories = List<Map<String, dynamic>>.from(data['serviceCategories'] ?? []); editServices(context, uid, categories); },
              icon: const Icon(Icons.build_outlined, size: 14), label: const Text('Services', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
            )),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                HapticFeedback.mediumImpact(); setSheetState(() => isSaving = true);
                try {
                  final updates = <String, dynamic>{'name': nameController.text.trim(), 'phone': phoneController.text.trim(), 'bio': bioController.text.trim(), 'updatedAt': FieldValue.serverTimestamp()};
                  if (photoUrl != null) { updates['photoUrl'] = photoUrl; updates['photoFileId'] = photoFileId; }
                  await FirebaseFirestore.instance.collection('profiles').doc(uid).update(updates);
                  HapticFeedback.heavyImpact(); Navigator.pop(ctx);
                } catch (e) { HapticFeedback.vibrate(); ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e'))); }
                setSheetState(() => isSaving = false);
              },
              child: const Text('Save'),
            ),
          ])),
        ),
      )),
    );
  }

  static void editServices(BuildContext context, String uid, List<Map<String, dynamic>> currentCategories) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.85, child: SafeArea(child: _EditServicesSheet(uid: uid, currentCategories: currentCategories))),
    );
  }

  static void gigHistory(BuildContext context, String uid) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).scaffoldBackgroundColor, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.7, child: SafeArea(child: _GigHistoryContent(uid: uid))));
  }

  static void reviews(BuildContext context, String uid) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).scaffoldBackgroundColor, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.7, child: SafeArea(child: _ReviewsContent(uid: uid))));
  }
}

// -- Edit Services Sheet --
class _EditServicesSheet extends StatefulWidget {
  final String uid;
  final List<Map<String, dynamic>> currentCategories;
  const _EditServicesSheet({required this.uid, required this.currentCategories});
  @override
  State<_EditServicesSheet> createState() => _EditServicesSheetState();
}

class _EditServicesSheetState extends State<_EditServicesSheet> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  late List<Map<String, dynamic>> _selectedCategories;
  Map<String, List<ServiceItem>> _categoryItems = {};
  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> _filteredCategories = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedCategories = List<Map<String, dynamic>>.from(widget.currentCategories);
    for (final cat in _selectedCategories) {
      final items = (cat['items'] as List<dynamic>?)?.map((i) => ServiceItem.fromJson(Map<String, dynamic>.from(i))).toList() ?? [];
      _categoryItems[cat['slug'] ?? ''] = items;
    }
    _fetchCategories();
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  Future<void> _fetchCategories() async {
    try {
      final response = await _supabase.from('services').select('name, slug, category').eq('active', true).order('name');
      if (mounted) setState(() { _allCategories = List<Map<String, dynamic>>.from(response); _filteredCategories = _allCategories; _isLoading = false; });
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _filterCategories(String query) {
    setState(() {
      if (query.isEmpty) { _filteredCategories = _allCategories; }
      else { _filteredCategories = _allCategories.where((s) => s['name'].toString().toLowerCase().contains(query.toLowerCase()) || s['category'].toString().toLowerCase().contains(query.toLowerCase())).toList(); }
    });
  }

  void _addCategory(String name, String slug) {
    HapticFeedback.selectionClick();
    setState(() { _selectedCategories.add({'slug': slug, 'name': name, 'items': []}); _categoryItems[slug] = []; });
  }

  void _removeCategory(int index) {
    HapticFeedback.selectionClick();
    setState(() { _categoryItems.remove(_selectedCategories[index]['slug'] ?? ''); _selectedCategories.removeAt(index); });
  }

  void _showAddItemsSheet(int categoryIndex) {
    final cat = _selectedCategories[categoryIndex];
    final slug = cat['slug'] ?? '';
    final name = cat['name'] ?? '';
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final items = List<ServiceItem>.from(_categoryItems[slug] ?? []);

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF6B7280).withAlpha(77), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('$name — Add Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyLarge?.color)),
            const SizedBox(height: 4),
            const Text('Add the specific services you offer and their prices.', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 16),
            if (items.isNotEmpty)
              ...items.asMap().entries.map((entry) => ListTile(
                contentPadding: EdgeInsets.zero, dense: true,
                title: Text(entry.value.name, style: const TextStyle(fontSize: 14)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('N${entry.value.price}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2D3BA0))),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () { items.removeAt(entry.key); setSheetState(() {}); }),
                ]),
              )),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: nameController, decoration: const InputDecoration(hintText: 'Service name (e.g. Basic Cut)', hintStyle: TextStyle(fontSize: 12), isDense: true), style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Price (N)', hintStyle: TextStyle(fontSize: 12), isDense: true, prefixText: 'N '), style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF2D3BA0)), onPressed: () {
                final itemName = nameController.text.trim();
                final price = int.tryParse(priceController.text.trim());
                if (itemName.isNotEmpty && price != null && price > 0) { items.add(ServiceItem(name: itemName, price: price)); nameController.clear(); priceController.clear(); setSheetState(() {}); }
              }),
            ]),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: priceController,
              builder: (context, value, child) {
                final price = int.tryParse(value.text.trim());
                if (price == null || price <= 0) return const SizedBox.shrink();
                final commission = (price * 0.12).round().clamp(0, 2000);
                final earnings = price - commission;
                final showHint = commission > 500;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF6B7280).withAlpha(51))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Platform fee (12%)', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        Text(commission >= 2000 ? '-N$commission (capped)' : '-N$commission', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      ]),
                      const SizedBox(height: 2),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('You\'ll earn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('N$earnings', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2D3BA0))),
                      ]),
                      if (showHint) ...[
                        const SizedBox(height: 4),
                        Text('Suggested price to earn N$price: N${((price / 0.88).round())}', style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280), fontStyle: FontStyle.italic)),
                      ],
                    ]),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () { _categoryItems[slug] = items; Navigator.pop(ctx); setState(() {}); },
              child: Text(items.isEmpty ? 'Skip' : 'Save Items (${items.length})'),
            ),
          ]),
        ),
      )),
    );
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact(); setState(() => _isSaving = true);
    try {
      final finalCategories = _selectedCategories.map((cat) {
        final slug = cat['slug'] ?? '';
        final items = _categoryItems[slug] ?? [];
        return {'slug': slug, 'name': cat['name'] ?? '', 'items': items.map((i) => i.toJson()).toList()};
      }).toList();

      await FirebaseFirestore.instance.collection('profiles').doc(widget.uid).update({'serviceCategories': finalCategories, 'updatedAt': FieldValue.serverTimestamp()});

      for (final cat in finalCategories) {
        for (final item in List<Map<String, dynamic>>.from(cat['items'] ?? [])) {
          final itemName = (item['name'] ?? '').toString().trim().toLowerCase();
          if (itemName.isNotEmpty) {
            await _supabase.from('provider_items').upsert({'item_name': itemName, 'category': cat['name'] ?? 'Other', 'provider_id': widget.uid, 'created_at': DateTime.now().toIso8601String()});
          }
        }
      }
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) { HapticFeedback.vibrate(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _isSaving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Edit Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        TextButton(onPressed: _isSaving ? null : _save, child: _isSaving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ])),
      if (_selectedCategories.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 6, runSpacing: 6, children: _selectedCategories.asMap().entries.map((entry) {
        final idx = entry.key; final slug = entry.value['slug'] ?? ''; final name = entry.value['name'] ?? ''; final items = _categoryItems[slug] ?? [];
        return Chip(label: Text(items.isNotEmpty ? '$name (${items.length})' : name, style: const TextStyle(color: Colors.white, fontSize: 12)), backgroundColor: const Color(0xFF2D3BA0), deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white), onDeleted: () => _removeCategory(idx), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)));
      }).toList()))),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(controller: _searchController, onChanged: _filterCategories, decoration: const InputDecoration(hintText: 'Search categories...', prefixIcon: Icon(Icons.search, size: 20), isDense: true))),
      const SizedBox(height: 8),
      Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _filteredCategories.length, itemBuilder: (context, index) {
        final cat = _filteredCategories[index]; final slug = cat['slug'] as String; final isSelected = _selectedCategories.any((c) => c['slug'] == slug); final selectedIdx = _selectedCategories.indexWhere((c) => c['slug'] == slug);
        return ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(cat['name'], style: const TextStyle(fontSize: 14)), subtitle: Text(cat['category'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))), trailing: isSelected ? TextButton(onPressed: () => _showAddItemsSheet(selectedIdx), child: Text('${(_categoryItems[slug] ?? []).length} items', style: const TextStyle(fontSize: 11))) : Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6B7280), width: 2))), onTap: () {
          if (isSelected) { _showAddItemsSheet(selectedIdx); } else { _addCategory(cat['name'], slug); WidgetsBinding.instance.addPostFrameCallback((_) { final newIdx = _selectedCategories.indexWhere((c) => c['slug'] == slug); if (newIdx != -1) _showAddItemsSheet(newIdx); }); }
          FocusScope.of(context).unfocus();
        });
      })),
    ]);
  }
}

// -- Gig History Content --
class _GigHistoryContent extends StatefulWidget { final String uid; const _GigHistoryContent({required this.uid}); @override State<_GigHistoryContent> createState() => _GigHistoryContentState(); }
class _GigHistoryContentState extends State<_GigHistoryContent> with SingleTickerProviderStateMixin {
  late TabController _tabController; final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  @override void initState() { super.initState(); _tabController = TabController(length: 2, vsync: this); }
  @override void dispose() { _tabController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Text('Gig History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))),
      TabBar(controller: _tabController, labelColor: const Color(0xFF1A1F71), unselectedLabelColor: const Color(0xFF6B7280), indicatorColor: const Color(0xFF1A1F71), tabs: const [Tab(text: 'As Provider'), Tab(text: 'As Client')]),
      Expanded(child: TabBarView(controller: _tabController, children: [_GigList(uid: widget.uid, role: 'provider'), _GigList(uid: widget.uid, role: 'client')])),
    ]);
  }
}

class _GigList extends StatefulWidget { final String uid; final String role; const _GigList({required this.uid, required this.role}); @override State<_GigList> createState() => _GigListState(); }
class _GigListState extends State<_GigList> {
  final ScrollController _scrollController = ScrollController(); final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _gigs = []; DocumentSnapshot? _lastDoc; bool _isLoading = true; bool _hasMore = true; bool _isLoadingMore = false; static const int _pageSize = 10;
  @override void initState() { super.initState(); _fetchGigs(); _scrollController.addListener(_onScroll); }
  @override void dispose() { _scrollController.dispose(); super.dispose(); }
  void _onScroll() { if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) _fetchMore(); }
  Future<void> _fetchGigs() async {
    try {
      final field = widget.role == 'provider' ? 'providerId' : 'clientId';
      final snapshot = await _firestore.collection('gigs').where(field, isEqualTo: widget.uid).orderBy('createdAt', descending: true).limit(_pageSize).get();
      if (mounted) setState(() { _gigs = snapshot.docs.map((d) => d.data()).toList(); _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null; _hasMore = snapshot.docs.length >= _pageSize; _isLoading = false; });
    } catch (e) { if (mounted) { showError(context, e); setState(() => _isLoading = false); } }
  }
  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return; setState(() => _isLoadingMore = true);
    try {
      final field = widget.role == 'provider' ? 'providerId' : 'clientId';
      final snapshot = await _firestore.collection('gigs').where(field, isEqualTo: widget.uid).orderBy('createdAt', descending: true).startAfterDocument(_lastDoc!).limit(_pageSize).get();
      if (mounted) setState(() { _gigs.addAll(snapshot.docs.map((d) => d.data())); _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null; _hasMore = snapshot.docs.length >= _pageSize; _isLoadingMore = false; });
    } catch (e) { if (mounted) { showError(context, e); setState(() => _isLoadingMore = false); } }
  }
  @override Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_gigs.isEmpty) return Center(child: Text('No gigs yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)));
    return ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: _gigs.length + (_hasMore ? 1 : 0), itemBuilder: (context, index) {
      if (index >= _gigs.length) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
      final g = _gigs[index]; final status = g['status'] ?? 'pending'; final service = g['service'] ?? ''; final createdAt = g['createdAt'] as Timestamp?;
      return Card(color: Theme.of(context).cardColor, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
        title: Text(service.replaceAll('-', ' '), style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
        subtitle: createdAt != null ? Text(DateFormat('dd MMM yyyy').format(createdAt.toDate()), style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))) : null,
        trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: status == 'completed' ? const Color(0xFF4CAF50).withAlpha(26) : status == 'cancelled' ? Colors.red.withAlpha(26) : Colors.orange.withAlpha(26), borderRadius: BorderRadius.circular(8)), child: Text(status == 'completed' ? 'Completed' : status == 'cancelled' ? 'Cancelled' : 'Pending', style: TextStyle(fontSize: 11, color: status == 'completed' ? const Color(0xFF4CAF50) : status == 'cancelled' ? Colors.red : Colors.orange))),
      ));
    });
  }
}

// -- Reviews Content --
class _ReviewsContent extends StatefulWidget { final String uid; const _ReviewsContent({required this.uid}); @override State<_ReviewsContent> createState() => _ReviewsContentState(); }
class _ReviewsContentState extends State<_ReviewsContent> {
  final ScrollController _scrollController = ScrollController(); final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _reviews = []; DocumentSnapshot? _lastDoc; bool _isLoading = true; bool _hasMore = true; bool _isLoadingMore = false; static const int _pageSize = 10;
  @override void initState() { super.initState(); _fetchReviews(); _scrollController.addListener(_onScroll); }
  @override void dispose() { _scrollController.dispose(); super.dispose(); }
  void _onScroll() { if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) _fetchMore(); }
  Future<void> _fetchReviews() async {
    try {
      final snapshot = await _firestore.collection('reviews').where('providerId', isEqualTo: widget.uid).orderBy('createdAt', descending: true).limit(_pageSize).get();
      if (mounted) setState(() { _reviews = snapshot.docs.map((d) => d.data()).toList(); _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null; _hasMore = snapshot.docs.length >= _pageSize; _isLoading = false; });
    } catch (e) { if (mounted) { showError(context, e); setState(() => _isLoading = false); } }
  }
  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return; setState(() => _isLoadingMore = true);
    try {
      final snapshot = await _firestore.collection('reviews').where('providerId', isEqualTo: widget.uid).orderBy('createdAt', descending: true).startAfterDocument(_lastDoc!).limit(_pageSize).get();
      if (mounted) setState(() { _reviews.addAll(snapshot.docs.map((d) => d.data())); _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null; _hasMore = snapshot.docs.length >= _pageSize; _isLoadingMore = false; });
    } catch (e) { if (mounted) { showError(context, e); setState(() => _isLoadingMore = false); } }
  }
  @override Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_reviews.isEmpty) return Center(child: Text('No reviews yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)));
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Text('Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))),
      Expanded(child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _reviews.length + (_hasMore ? 1 : 0), itemBuilder: (context, index) {
        if (index >= _reviews.length) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
        final r = _reviews[index]; final rating = (r['rating'] ?? 0).toInt(); final text = r['text'] ?? ''; final createdAt = r['createdAt'] as Timestamp?;
        return Card(color: Theme.of(context).cardColor, margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [...List.generate(5, (i) => Icon(Icons.star, size: 16, color: i < rating ? Colors.amber : const Color(0xFF6B7280).withAlpha(77))), const Spacer(), if (createdAt != null) Text(DateFormat('dd MMM yyyy').format(createdAt.toDate()), style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)))]),
          if (text.isNotEmpty) ...[const SizedBox(height: 8), Text(text, style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color))],
        ])));
      })),
    ]);
  }
}
