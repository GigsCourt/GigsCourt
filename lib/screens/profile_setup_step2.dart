import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class ServiceCategory {
  final String slug;
  final String name;
  final List<ServiceItem> items;

  ServiceCategory({required this.slug, required this.name, List<ServiceItem>? items})
      : items = items ?? [];

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      slug: json['slug'] ?? '',
      name: json['name'] ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => ServiceItem.fromJson(Map<String, dynamic>.from(i)))
              .toList() ??
          [],
    );
  }
}

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

class ProfileSetupStep2 extends StatefulWidget {
  final List<Map<String, dynamic>>? initialCategories;
  final Function(List<Map<String, dynamic>> categories) onChanged;

  const ProfileSetupStep2({
    super.key,
    this.initialCategories,
    required this.onChanged,
  });

  @override
  State<ProfileSetupStep2> createState() => _ProfileSetupStep2State();
}

class _ProfileSetupStep2State extends State<ProfileSetupStep2> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _allCategories = [];
  late List<ServiceCategory> _selectedCategories;
  Map<String, List<ServiceItem>> _categoryItems = {};
  bool _isLoading = true;
  bool _showDropdown = false;
  OverlayEntry? _dropdownOverlay;
  List<Map<String, dynamic>> _filteredSuggestions = [];
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _selectedCategories = (widget.initialCategories ?? [])
        .map((c) => ServiceCategory.fromJson(c))
        .toList();
    _fetchCategories();
    _searchController.addListener(() => _filterSuggestions(_searchController.text));
    _searchFocusNode.addListener(() { if (!_searchFocusNode.hasFocus) _removeDropdown(); });
  }

  @override
  void dispose() {
    _removeDropdown();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await _supabase.from('services').select('name, slug, category').eq('active', true).order('category').order('name');
      if (mounted) setState(() { _allCategories = List<Map<String, dynamic>>.from(response); _isLoading = false; });
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _filterSuggestions(String query) {
    if (query.isEmpty) { _removeDropdown(); setState(() { _filteredSuggestions = []; _showDropdown = false; }); return; }
    final selectedSlugs = _selectedCategories.map((c) => c.slug).toList();
    final filtered = _allCategories.where((c) {
      final name = c['name'].toString().toLowerCase(); final category = c['category'].toString().toLowerCase();
      final q = query.toLowerCase(); final slug = c['slug'] as String;
      return (name.contains(q) || category.contains(q)) && !selectedSlugs.contains(slug);
    }).toList();
    setState(() { _filteredSuggestions = filtered; _showDropdown = filtered.isNotEmpty; });
    if (filtered.isNotEmpty) { _showDropdownOverlay(); } else { _removeDropdown(); }
  }

  void _showDropdownOverlay() {
    _removeDropdown();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    _dropdownOverlay = OverlayEntry(builder: (context) => Positioned(width: renderBox.size.width - 48, child: CompositedTransformFollower(link: _layerLink, showWhenUnlinked: false, offset: const Offset(24, 60), child: Material(elevation: 8, borderRadius: BorderRadius.circular(12), color: Theme.of(context).cardColor, child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 200), child: ListView.builder(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: _filteredSuggestions.length, itemBuilder: (context, index) {
      final cat = _filteredSuggestions[index];
      return ListTile(dense: true, title: Text(cat['name'], style: const TextStyle(fontSize: 13)), subtitle: Text(cat['category'], style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))), onTap: () { _addCategory(cat['name'], cat['slug']); _searchController.clear(); _removeDropdown(); FocusScope.of(context).unfocus(); });
    }))))));
    overlay.insert(_dropdownOverlay!);
  }

  void _removeDropdown() { _dropdownOverlay?.remove(); _dropdownOverlay = null; if (mounted) setState(() => _showDropdown = false); }

  void _addCategory(String name, String slug) { HapticFeedback.selectionClick(); setState(() { _selectedCategories.add(ServiceCategory(slug: slug, name: name)); _notifyParent(); }); }

  void _removeCategory(int index) { HapticFeedback.selectionClick(); setState(() { _categoryItems.remove(_selectedCategories[index].slug); _selectedCategories.removeAt(index); _notifyParent(); }); }

  void _showAddItemsSheet(int categoryIndex) {
    final category = _selectedCategories[categoryIndex];
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final items = List<ServiceItem>.from(_categoryItems[category.slug] ?? category.items);

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF6B7280).withAlpha(77), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('${category.name} — Add Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(ctx).textTheme.bodyLarge?.color)),
            const SizedBox(height: 4),
            const Text('Add the specific services you offer and their prices.', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 16),
            if (items.isNotEmpty)
              ...items.asMap().entries.map((entry) => ListTile(
                contentPadding: EdgeInsets.zero, dense: true, title: Text(entry.value.name, style: const TextStyle(fontSize: 14)),
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
                final name = nameController.text.trim(); final price = int.tryParse(priceController.text.trim());
                if (name.isNotEmpty && price != null && price > 0) { items.add(ServiceItem(name: name, price: price)); nameController.clear(); priceController.clear(); setSheetState(() {}); }
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
              onPressed: () { _categoryItems[category.slug] = items; Navigator.pop(ctx); setState(() => _notifyParent()); },
              child: Text(items.isEmpty ? 'Skip' : 'Save Items (${items.length})'),
            ),
          ]),
        ),
      )),
    );
  }

  void _notifyParent() {
    final categories = _selectedCategories.map((c) {
      final items = _categoryItems[c.slug] ?? c.items;
      return ServiceCategory(slug: c.slug, name: c.name, items: items).toJson();
    }).toList();
    widget.onChanged(categories);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: TextField(controller: _searchController, focusNode: _searchFocusNode, decoration: const InputDecoration(hintText: 'Search categories...', hintStyle: TextStyle(fontSize: 13), prefixIcon: Icon(Icons.search, size: 20), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
        const SizedBox(height: 8),
        if (_selectedCategories.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Wrap(spacing: 6, runSpacing: 6, children: _selectedCategories.asMap().entries.map((entry) {
            final idx = entry.key; final cat = entry.value; final items = _categoryItems[cat.slug] ?? cat.items;
            return Chip(label: Text(items.isNotEmpty ? '${cat.name} (${items.length})' : cat.name, style: const TextStyle(color: Colors.white, fontSize: 12)), backgroundColor: AppTheme.royalBlue, deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white), onDeleted: () => _removeCategory(idx), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)));
          }).toList()))),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withAlpha(77))), child: Row(children: [const Icon(Icons.lightbulb_outline, size: 16, color: Colors.orange), const SizedBox(width: 6), Expanded(child: Text('Select a category, then add your services with prices. Clients will see these when they search.', style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color, height: 1.3)))]))),
        const SizedBox(height: 12),
        Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 24), itemCount: _allCategories.length + 1, itemBuilder: (context, index) {
          if (index == 0) return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Available Categories', style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color, fontWeight: FontWeight.w600)));
          final cat = _allCategories[index - 1]; final slug = cat['slug'] as String; final isSelected = _selectedCategories.any((c) => c.slug == slug); final selectedIdx = _selectedCategories.indexWhere((c) => c.slug == slug);
          return ListTile(contentPadding: EdgeInsets.zero, dense: true, visualDensity: VisualDensity.compact, title: Text(cat['name'], style: const TextStyle(fontSize: 13)), subtitle: Text(cat['category'], style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))), trailing: isSelected ? TextButton(onPressed: () => _showAddItemsSheet(selectedIdx), child: Text('${(_categoryItems[slug] ?? _selectedCategories[selectedIdx].items).length} items', style: const TextStyle(fontSize: 11))) : Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.transparent, border: Border.all(color: const Color(0xFF6B7280), width: 2))), onTap: () {
            if (isSelected) { _showAddItemsSheet(selectedIdx); } else { _addCategory(cat['name'], slug); WidgetsBinding.instance.addPostFrameCallback((_) { final newIdx = _selectedCategories.indexWhere((c) => c.slug == slug); if (newIdx != -1) _showAddItemsSheet(newIdx); }); }
            FocusScope.of(context).unfocus();
          });
        })),
      ]),
    );
  }
}
