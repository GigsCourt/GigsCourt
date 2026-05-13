import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Admin', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF1A1F71),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF1A1F71),
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Users'),
            Tab(text: 'Services'),
            Tab(text: 'Revenue'),
            Tab(text: 'Providers'),
            Tab(text: 'Issues'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DashboardTab(),
          _UsersTab(),
          _ServicesTab(),
          _RevenueTab(),
          _ProvidersTab(),
          _IssuesTab(),
        ],
      ),
    );
  }
}

// -- Dashboard Tab --
class _DashboardTab extends StatefulWidget {
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _totalUsers = 0;
  int _activeToday = 0;
  int _totalGigs = 0;
  int _revenue = 0;
  int _completedGigs = 0;
  int _pendingGigs = 0;
  int _cancelledGigs = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final profiles = await _firestore.collection('profiles').count().get();
      final gigs = await _firestore.collection('gigs').get();
      final purchases = await _firestore.collection('credit_purchases').where('status', isEqualTo: 'completed').get();

      int completed = 0, pending = 0, cancelled = 0, revenue = 0;
      for (final doc in gigs.docs) {
        final status = doc.data()['status'] ?? '';
        if (status == 'completed') completed++;
        if (status == 'pending') pending++;
        if (status == 'cancelled') cancelled++;
      }
      for (final doc in purchases.docs) {
        revenue += (doc.data()['amount'] ?? 0).toInt();
      }

      if (mounted) {
        setState(() {
          _totalUsers = profiles.count;
          _totalGigs = gigs.docs.length;
          _completedGigs = completed;
          _pendingGigs = pending;
          _cancelledGigs = cancelled;
          _revenue = revenue;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStatCard('Total Users', _totalUsers.toString(), Icons.people_outline),
          const SizedBox(height: 8),
          _buildStatCard('Total Gigs', _totalGigs.toString(), Icons.work_outline),
          const SizedBox(height: 8),
          _buildStatCard('Revenue', '₦$_revenue', Icons.monetization_on_outlined),
          const SizedBox(height: 20),
          Text('Gig Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 12),
          _buildGigBar('Completed', _completedGigs, const Color(0xFF4CAF50)),
          _buildGigBar('Pending', _pendingGigs, Colors.orange),
          _buildGigBar('Cancelled', _cancelledGigs, Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A1F71)),
        title: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        subtitle: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ),
    );
  }

  Widget _buildGigBar(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 13)),
          const Spacer(),
          Text(count.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        ],
      ),
    );
  }
}

// -- Users Tab --
class _UsersTab extends StatefulWidget {
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final snapshot = await _firestore.collection('profiles').orderBy('name').get();
      if (mounted) {
        setState(() {
          _users = snapshot.docs.map((d) => d.data()..['uid'] = d.id).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _giftCredits(String uid, String name) async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gift Credits to $name'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Credits amount')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text) ?? 0), child: const Text('Send')),
        ],
      ),
    );

    if (amount != null && amount > 0) {
      final doc = await _firestore.collection('profiles').doc(uid).get();
      final current = (doc.data()?['credits'] ?? 0).toInt();
      await _firestore.collection('profiles').doc(uid).update({'credits': current + amount});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$amount credits sent to $name')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: const InputDecoration(hintText: 'Search by name...', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final u = filtered[index];
                    final name = u['name'] ?? 'Unknown';
                    final email = u['uid'] ?? '';
                    final gigs = (u['gigCount'] ?? 0).toInt();
                    final credits = (u['credits'] ?? 0).toInt();
                    return ListTile(
                      title: Text(name, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                      subtitle: Text('Gigs: $gigs · Credits: $credits', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      trailing: TextButton(
                        onPressed: () => _giftCredits(u['uid'] ?? '', name),
                        child: const Text('Gift Credits'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// -- Services Tab --
class _ServicesTab extends StatefulWidget {
  @override
  State<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<_ServicesTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final services = await _firestore.collection('services').orderBy('name').get();
      final suggestions = await _firestore.collection('service_suggestions').where('status', isEqualTo: 'pending').get();
      if (mounted) {
        setState(() {
          _services = services.docs.map((d) => d.data()..['id'] = d.id).toList();
          _suggestions = suggestions.docs.map((d) => d.data()..['id'] = d.id).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addService() async {
    final nameController = TextEditingController();
    final categoryController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Service Name')),
            const SizedBox(height: 8),
            TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'Category')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, {'name': nameController.text.trim(), 'category': categoryController.text.trim()}), child: const Text('Add')),
        ],
      ),
    );

    if (result != null && result['name']!.isNotEmpty) {
      final slug = result['name']!.toLowerCase().replaceAll(' ', '-');
      await _firestore.collection('services').add({
        'name': result['name'], 'slug': slug, 'category': result['category'], 'active': true,
      });
      _loadData();
    }
  }

  Future<void> _approveSuggestion(Map<String, dynamic> suggestion) async {
    final slug = (suggestion['name'] as String).toLowerCase().replaceAll(' ', '-');
    await _firestore.collection('services').add({
      'name': suggestion['name'], 'slug': slug, 'category': suggestion['category'] ?? '', 'active': true,
    });
    await _firestore.collection('service_suggestions').doc(suggestion['id']).update({'status': 'approved'});
    _loadData();
  }

  Future<void> _toggleService(Map<String, dynamic> service) async {
    final active = service['active'] ?? true;
    await _firestore.collection('services').doc(service['id']).update({'active': !active});
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Service Catalog', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
              ElevatedButton(onPressed: _addService, child: const Text('Add Service')),
            ],
          ),
          const SizedBox(height: 8),
          ..._services.map((s) => ListTile(
                title: Text(s['name'] ?? '', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                subtitle: Text(s['category'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s['active'] == true ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, color: s['active'] == true ? const Color(0xFF4CAF50) : const Color(0xFF6B7280))),
                  const SizedBox(width: 8),
                  IconButton(icon: Icon(s['active'] == true ? Icons.toggle_on : Icons.toggle_off, color: s['active'] == true ? const Color(0xFF4CAF50) : const Color(0xFF6B7280)), onPressed: () => _toggleService(s)),
                ]),
              )),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Service Suggestions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 8),
            ..._suggestions.map((s) => ListTile(
                  title: Text(s['name'] ?? '', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.check, color: Color(0xFF4CAF50)), onPressed: () => _approveSuggestion(s)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () async {
                      await _firestore.collection('service_suggestions').doc(s['id']).update({'status': 'rejected'});
                      _loadData();
                    }),
                  ]),
                )),
          ],
        ],
      ),
    );
  }
}

// -- Revenue Tab --
class _RevenueTab extends StatefulWidget {
  @override
  State<_RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends State<_RevenueTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _purchases = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  Future<void> _loadPurchases() async {
    try {
      final snapshot = await _firestore.collection('credit_purchases').where('status', isEqualTo: 'completed').orderBy('createdAt', descending: true).get();
      if (mounted) {
        setState(() {
          _purchases = snapshot.docs.map((d) => d.data()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _weekRevenue() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return _revenueForPeriod(weekStart, now);
  }

  int _monthRevenue() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return _revenueForPeriod(monthStart, now);
  }

  int _revenueForPeriod(DateTime start, DateTime end) {
    return _purchases.where((p) {
      final date = (p['createdAt'] as Timestamp?)?.toDate();
      return date != null && date.isAfter(start) && date.isBefore(end.add(const Duration(days: 1)));
    }).fold<int>(0, (sum, p) => sum + (p['amount'] ?? 0).toInt());
  }

  Map<int, Map<int, int>> _yearlyRevenue() {
    final result = <int, Map<int, int>>{};
    for (final p in _purchases) {
      final date = (p['createdAt'] as Timestamp?)?.toDate();
      if (date != null) {
        result[date.year] ??= {};
        result[date.year]![date.month] = (result[date.year]![date.month] ?? 0) + (p['amount'] ?? 0).toInt();
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final yearly = _yearlyRevenue();
    final years = yearly.keys.toList()..sort((a, b) => b.compareTo(a));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This Week', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 4),
          Text('₦${_weekRevenue()}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1F71))),
          const SizedBox(height: 16),
          Text('This Month', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 4),
          Text('₦${_monthRevenue()}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1F71))),
          const SizedBox(height: 24),
          Text('Yearly', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
          const SizedBox(height: 8),
          ...years.map((year) => _buildYearTile(year, yearly[year] ?? {})),
        ],
      ),
    );
  }

  Widget _buildYearTile(int year, Map<int, int> months) {
    final total = months.values.fold<int>(0, (a, b) => a + b);
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final sortedMonths = months.keys.toList()..sort();

    return Card(
      color: Theme.of(context).cardColor,
      child: ExpansionTile(
        title: Text(year.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
        subtitle: Text('₦$total', style: const TextStyle(color: Color(0xFF1A1F71))),
        children: sortedMonths.map((m) => ListTile(
          title: Text(monthNames[m], style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
          trailing: Text('₦${months[m] ?? 0}', style: const TextStyle(color: Color(0xFF1A1F71))),
        )).toList(),
      ),
    );
  }
}

// -- Providers Tab --
class _ProvidersTab extends StatefulWidget {
  @override
  State<_ProvidersTab> createState() => _ProvidersTabState();
}

class _ProvidersTabState extends State<_ProvidersTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _providers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    try {
      final snapshot = await _firestore.collection('profiles').orderBy('gigCount', descending: true).limit(50).get();
      if (mounted) {
        setState(() {
          _providers = snapshot.docs.map((d) => d.data()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _providers.length,
      itemBuilder: (context, index) {
        final p = _providers[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: NetworkImage(p['photoUrl'] ?? ''),
            child: const Icon(Icons.person),
          ),
          title: Text('${index + 1}. ${p['name'] ?? ''}', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
          subtitle: Text('${p['gigCount'] ?? 0} gigs · ${p['rating']?.toStringAsFixed(1) ?? '0.0'}★', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        );
      },
    );
  }
}

// -- Issues Tab --
class _IssuesTab extends StatefulWidget {
  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _responseController = TextEditingController();
  List<Map<String, dynamic>> _issues = [];
  bool _isLoading = true;

  static const _presetResponses = [
    'Thank you for reporting. We are investigating this issue.',
    'This has been resolved. Please check again.',
    'We need more information. Can you provide details?',
    'This is a known issue and we are working on a fix.',
    'Thank you for your patience. The issue has been addressed.',
    'Please update the app to the latest version.',
    'This feature is coming soon. Stay tuned!',
    'We have forwarded this to our team.',
  ];

  @override
  void initState() {
    super.initState();
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    try {
      final snapshot = await _firestore.collection('reported_issues').orderBy('createdAt', descending: true).get();
      if (mounted) {
        setState(() {
          _issues = snapshot.docs.map((d) => d.data()..['id'] = d.id).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolve(String id, String response) async {
    await _firestore.collection('reported_issues').doc(id).update({'status': 'resolved', 'response': response});
    _loadData();
  }

  void _showResponseDialog(Map<String, dynamic> issue) {
    _responseController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Respond to Issue'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(issue['message'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              TextField(controller: _responseController, maxLines: 3, decoration: const InputDecoration(labelText: 'Response', hintText: 'Type or select a preset...')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _presetResponses.map((pr) => ActionChip(
                  label: Text(pr, style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    _responseController.text = pr;
                  },
                )).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            _resolve(issue['id'], _responseController.text.trim());
          }, child: const Text('Resolve')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_issues.isEmpty) return Center(child: Text('No issues reported', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _issues.length,
      itemBuilder: (context, index) {
        final issue = _issues[index];
        final status = issue['status'] ?? 'pending';
        return Card(
          color: Theme.of(context).cardColor,
          child: ListTile(
            title: Text(issue['subject'] ?? '', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                if (issue['response'] != null && (issue['response'] as String).isNotEmpty)
                  Text('Response: ${issue['response']}', style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50))),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'resolved' ? const Color(0xFF4CAF50).withAlpha(26) : Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status == 'resolved' ? 'Resolved' : 'Pending', style: TextStyle(fontSize: 11, color: status == 'resolved' ? const Color(0xFF4CAF50) : Colors.orange)),
            ),
            onTap: status == 'pending' ? () => _showResponseDialog(issue) : null,
          ),
        );
      },
    );
  }
}
