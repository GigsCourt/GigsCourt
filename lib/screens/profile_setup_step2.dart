import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  late List<String> _selectedServices;
  List<Map<String, dynamic>> _allServices = [];
  List<Map<String, dynamic>> _filteredServices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedServices = List<String>.from(widget.initialServices);
    _fetchServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _suggestController.dispose();
    super.dispose();
  }

  Future<void> _fetchServices() async {
    try {
      final response = await _supabase
          .from('services')
          .select('name, slug, category')
          .eq('active', true)
          .order('category')
          .order('name');

      setState(() {
        _allServices = List<Map<String, dynamic>>.from(response);
        _filteredServices = _allServices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterServices(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredServices = _allServices;
      } else {
        _filteredServices = _allServices
            .where((s) =>
                s['name'].toString().toLowerCase().contains(query.toLowerCase()) ||
                s['category'].toString().toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleService(String slug) {
    setState(() {
      if (_selectedServices.contains(slug)) {
        _selectedServices.remove(slug);
      } else {
        _selectedServices.add(slug);
      }
      widget.onChanged(_selectedServices);
    });
  }

  Future<void> _suggestService() async {
    final text = _suggestController.text.trim();
    if (text.isEmpty) return;

    try {
      await _supabase.from('service_suggestions').insert({
        'name': text,
        'status': 'pending',
      });

      _suggestController.clear();
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
    return Column(
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _searchController,
            onChanged: _filterServices,
            decoration: const InputDecoration(
              hintText: 'Search services...',
              prefixIcon: Icon(Icons.search),
              suffixIcon: Icon(Icons.tune),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Selected services as chips
        if (_selectedServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedServices.map((slug) {
                return Chip(
                  label: Text(
                    _slugToName(slug),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  backgroundColor: const Color(0xFF1A1F71),
                  deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                  onDeleted: () => _toggleService(slug),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
        // Hint
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.orange.withAlpha(77),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You won\'t appear in searches or nearby providers without at least one service. You can add services later in your profile.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Service list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _filteredServices.length + 2, // +2 for heading and suggest
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Available Services',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    if (index == _filteredServices.length + 1) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Can't find your service? Type it here.",
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _suggestController,
                                    decoration: const InputDecoration(
                                      hintText: 'e.g. Drone Pilot',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _suggestService,
                                  child: const Text('Suggest'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }
                    final service = _filteredServices[index - 1];
                    final slug = service['slug'] as String;
                    final isSelected = _selectedServices.contains(slug);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        service['name'],
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        service['category'],
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFF6B7280),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                      onTap: () => _toggleService(slug),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
