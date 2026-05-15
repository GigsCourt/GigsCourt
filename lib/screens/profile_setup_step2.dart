import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class ProfileSetupStep2 extends StatefulWidget {
  final List<String> initialServices;
  final Function(List<String> services) onChanged;

  const ProfileSetupStep2({
    super.key,
    required this.initialServices,
    required this.onChanged,
  });

  @override
  State<ProfileSetupStep2> createState() => _ProfileSetupStep2State();
}

class _ProfileSetupStep2State extends State<ProfileSetupStep2> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _suggestController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _suggestFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  late List<String> _selectedServices;
  List<Map<String, dynamic>> _allServices = [];
  List<Map<String, dynamic>> _filteredSuggestions = [];
  bool _isLoading = true;
  bool _showDropdown = false;
  OverlayEntry? _dropdownOverlay;

  @override
  void initState() {
    super.initState();
    _selectedServices = List<String>.from(widget.initialServices);
    _fetchServices();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        _removeDropdown();
      }
    });
  }

  @override
  void dispose() {
    _removeDropdown();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _suggestController.dispose();
    _searchFocusNode.dispose();
    _suggestFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterSuggestions(_searchController.text);
  }

  Future<void> _fetchServices() async {
    try {
      final response = await _supabase
          .from('services')
          .select('name, slug, category')
          .eq('active', true)
          .order('name');

      setState(() {
        _allServices = List<Map<String, dynamic>>.from(response);
        _allServices.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterSuggestions(String query) {
    if (query.isEmpty) {
      _removeDropdown();
      setState(() {
        _filteredSuggestions = [];
        _showDropdown = false;
      });
      return;
    }

    final filtered = _allServices.where((s) {
      final name = s['name'].toString().toLowerCase();
      final category = s['category'].toString().toLowerCase();
      final q = query.toLowerCase();
      // Exclude already selected services from suggestions
      final slug = s['slug'] as String;
      return (name.contains(q) || category.contains(q)) && !_selectedServices.contains(slug);
    }).toList();

    // Sort alphabetically
    filtered.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

    setState(() {
      _filteredSuggestions = filtered;
      _showDropdown = filtered.isNotEmpty;
    });

    if (filtered.isNotEmpty) {
      _showDropdownOverlay();
    } else {
      _removeDropdown();
    }
  }

  void _showDropdownOverlay() {
    _removeDropdown();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _dropdownOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: renderBox.size.width - 48,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(24, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).cardColor,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _filteredSuggestions.length,
                itemBuilder: (context, index) {
                  final service = _filteredSuggestions[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      service['name'],
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      service['category'],
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                    onTap: () {
                      _toggleService(service['slug'] as String);
                      _searchController.clear();
                      _removeDropdown();
                      FocusScope.of(context).unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_dropdownOverlay!);
  }

  void _removeDropdown() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
    if (mounted) {
      setState(() => _showDropdown = false);
    }
  }

  void _toggleService(String slug) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedServices.contains(slug)) {
        _selectedServices.remove(slug);
      } else {
        _selectedServices.add(slug);
      }
      widget.onChanged(_selectedServices);
      // Refresh suggestions to exclude selected
      if (_searchController.text.isNotEmpty) {
        _filterSuggestions(_searchController.text);
      }
    });
  }

  Future<void> _suggestService() async {
    final text = _suggestController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    try {
      await _supabase.from('service_suggestions').insert({
        'name': text,
        'status': 'pending',
      });

      _suggestController.clear();
      FocusScope.of(context).unfocus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service suggested! An admin will review it.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _slugToName(String slug) {
    final service = _allServices.firstWhere(
      (s) => s['slug'] == slug,
      orElse: () => {'name': slug},
    );
    return service['name'] ?? slug;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) {
                // Triggered via listener
              },
              decoration: const InputDecoration(
                hintText: 'Search services...',
                hintStyle: TextStyle(fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Selected services as chips
          if (_selectedServices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedServices.map((slug) {
                  return Chip(
                    label: Text(
                      _slugToName(slug),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: AppTheme.royalBlue,
                    deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
                    onDeleted: () => _toggleService(slug),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 12),
          // Hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withAlpha(77),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You won\'t appear in searches without at least one service. You can add more later.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Service list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _allServices.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Available Services',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      if (index == _allServices.length + 1) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Can't find your service? Suggest it here.",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _suggestController,
                                      focusNode: _suggestFocusNode,
                                      decoration: const InputDecoration(
                                        hintText: 'e.g. Drone Pilot',
                                        hintStyle: TextStyle(fontSize: 12),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 34,
                                    child: ElevatedButton(
                                      onPressed: _suggestService,
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        textStyle: const TextStyle(fontSize: 12),
                                      ),
                                      child: const Text('Suggest'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }
                      final service = _allServices[index - 1];
                      final slug = service['slug'] as String;
                      final isSelected = _selectedServices.contains(slug);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          service['name'],
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          service['category'],
                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                        trailing: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? AppTheme.royalBlue : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? AppTheme.royalBlue : const Color(0xFF6B7280),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 12, color: Colors.white)
                              : null,
                        ),
                        onTap: () {
                          _toggleService(slug);
                          FocusScope.of(context).unfocus();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
