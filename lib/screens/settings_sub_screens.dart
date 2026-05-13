import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Credit History Full Screen
class CreditHistoryScreen extends StatefulWidget {
  const CreditHistoryScreen({super.key});

  @override
  State<CreditHistoryScreen> createState() => _CreditHistoryScreenState();
}

class _CreditHistoryScreenState extends State<CreditHistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _purchases = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _fetchPurchases();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchMore();
    }
  }

  Future<void> _fetchPurchases() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('credit_purchases')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _purchases = snapshot.docs.map((d) => d.data()).toList();
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('credit_purchases')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _purchases.addAll(snapshot.docs.map((d) => d.data()));
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Credit History', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _purchases.isEmpty
              ? Center(
                  child: Text('No purchases yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _purchases.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _purchases.length) {
                      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                    }
                    final p = _purchases[index];
                    final amount = (p['amount'] ?? 0).toInt();
                    final credits = (p['credits'] ?? 0).toInt();
                    final reference = p['reference'] ?? '';
                    final status = p['status'] ?? 'pending';
                    final createdAt = p['createdAt'] as Timestamp?;

                    return Card(
                      color: Theme.of(context).cardColor,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('₦$amount → $credits Credits', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ref: $reference', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                            if (createdAt != null)
                              Text(DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toDate()),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'completed'
                                ? const Color(0xFF4CAF50).withAlpha(26)
                                : Colors.orange.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status == 'completed' ? 'Completed' : 'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              color: status == 'completed' ? const Color(0xFF4CAF50) : Colors.orange,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// Support Full Screen
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Support', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1A1F71),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF1A1F71),
          tabs: const [
            Tab(text: 'Report Issue'),
            Tab(text: 'My Tickets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReportIssueTab(),
          _MyTicketsTab(),
        ],
      ),
    );
  }
}

class _ReportIssueTab extends StatefulWidget {
  @override
  State<_ReportIssueTab> createState() => _ReportIssueTabState();
}

class _ReportIssueTabState extends State<_ReportIssueTab> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.collection('reported_issues').add({
        'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'subject': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
        'status': 'pending',
        'response': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _subjectController.clear();
      _messageController.clear();
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue submitted. We will get back to you.')),
        );
      }
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _subjectController,
              decoration: const InputDecoration(labelText: 'Subject'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Subject is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _messageController,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Message is required' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Ticket'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyTicketsTab extends StatefulWidget {
  @override
  State<_MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<_MyTicketsTab> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _tickets = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchMore();
    }
  }

  Future<void> _fetchTickets() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('reported_issues')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _tickets = snapshot.docs.map((d) => d.data()).toList();
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('reported_issues')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _tickets.addAll(snapshot.docs.map((d) => d.data()));
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
    if (_tickets.isEmpty) {
      return Center(child: Text('No tickets yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _tickets.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _tickets.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
        }
        final t = _tickets[index];
        final status = t['status'] ?? 'pending';
        final response = t['response'] ?? '';
        final createdAt = t['createdAt'] as Timestamp?;

        return Card(
          color: Theme.of(context).cardColor,
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(t['subject'] ?? '', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['message'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                if (createdAt != null)
                  Text(DateFormat('dd MMM yyyy').format(createdAt.toDate()), style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'resolved' ? const Color(0xFF4CAF50).withAlpha(26) : Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status == 'resolved' ? 'Resolved' : 'Pending',
                style: TextStyle(fontSize: 11, color: status == 'resolved' ? const Color(0xFF4CAF50) : Colors.orange),
              ),
            ),
            children: [
              if (response.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Response: $response', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Legal Full Screen
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Terms & Privacy', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1A1F71),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF1A1F71),
          tabs: const [
            Tab(text: 'Terms of Service'),
            Tab(text: 'Privacy Policy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LegalTextTab(content: _termsOfService),
          _LegalTextTab(content: _privacyPolicy),
        ],
      ),
    );
  }
}

class _LegalTextTab extends StatelessWidget {
  final String content;
  const _LegalTextTab({required this.content});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        content,
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}

const String _termsOfService = '''TERMS OF SERVICE

Last Updated: May 2026

1. ACCEPTANCE OF TERMS
By creating an account or using GigsCourt ("the App"), you agree to these Terms of Service. If you do not agree, do not use the App.

2. ACCOUNT REGISTRATION
You must provide a valid email address and create a password to register. You are responsible for maintaining the confidentiality of your account credentials. You must be at least 13 years old to use GigsCourt.

3. USER ROLES
GigsCourt allows users to act as Providers (offering services) or Clients (seeking services). You may use the App in either role or both.

4. SERVICES AND GIGS
Providers may list services they offer. A "Gig" is created when a Provider registers a service agreement with a Client through the App. Gigs are voluntary agreements between users. GigsCourt is not a party to any gig agreement and does not guarantee the quality of services provided.

5. CREDITS AND PAYMENTS
Credits are required to register gigs and enable reviews. Credit packages are purchased through Paystack, a third-party payment processor. All payments are final and non-refundable unless required by applicable law. GigsCourt is not responsible for payment processing errors caused by Paystack.

6. REVIEWS AND RATINGS
After a gig is completed, Clients may submit a rating (1-5 stars) and an optional review. Reviews are tied to your account and are publicly visible on your profile. GigsCourt reserves the right to remove reviews that violate our content policies.

7. USER CONDUCT
You agree not to: provide false or misleading information; harass, threaten, or abuse other users; use the App for any illegal purpose; attempt to manipulate ratings or reviews; share content that is obscene, offensive, or violates others' rights.

8. LOCATION DATA
GigsCourt uses your device location to show nearby providers and to display your workspace location if you are a Provider. You may disable location access in your device settings, but this will limit App functionality.

9. INTELLECTUAL PROPERTY
The GigsCourt name, logo, and App design are owned by GigsCourt. Photos and content you upload remain yours. By uploading content, you grant GigsCourt permission to display it within the App.

10. LIMITATION OF LIABILITY
GigsCourt is provided "as is" without warranties of any kind. We are not liable for disputes between users, service quality, or any damages arising from use of the App.

11. TERMINATION
We may suspend or terminate your account if you violate these Terms. You may delete your account at any time through the App settings.

12. CHANGES TO TERMS
We may update these Terms. Continued use of the App after changes means you accept the new Terms.

13. GOVERNING LAW
These Terms are governed by the laws of the Federal Republic of Nigeria.

14. CONTACT
For questions about these Terms, contact us through the Support section in the App.''';

const String _privacyPolicy = '''PRIVACY POLICY

Last Updated: May 2026

1. INFORMATION WE COLLECT
When you use GigsCourt, we collect: email address (required for account creation); full name or business name; phone number (optional); bio or description (optional); profile photo (optional); work photos (optional); workspace address and location; device location (with your permission); chat messages exchanged with other users; gig history and reviews.

2. HOW WE USE YOUR INFORMATION
We use your information to: create and manage your account; display your profile to other users; show nearby providers based on location; enable communication between users; process credit purchases; improve the App.

3. DATA STORAGE
Your data is stored on Firebase (Google Cloud) for account, profiles, chats, gigs, and reviews; Supabase for location data and service catalog; ImageKit for profile photos and work photos. These services comply with international data protection standards.

4. LOCATION DATA
With your permission, we collect your device location to show providers near you. If you are a Provider, your workspace location is visible to other users. You can change your workspace location or disable location access at any time.

5. CHAT DATA
Chat messages are stored to enable conversation history. Messages are accessible only to the conversation participants. We do not monitor or read your messages unless required to investigate a reported violation.

6. PHOTOS AND MEDIA
Photos you upload are stored on ImageKit. Your profile photo and work photos are publicly visible to other users. You can delete your photos at any time through the App.

7. THIRD-PARTY SERVICES
We use Paystack for processing credit purchases and ImageKit for photo storage and delivery. These services have their own privacy policies.

8. DATA RETENTION
We retain your data as long as your account exists. If you delete your account, your data is permanently removed from all our systems.

9. YOUR RIGHTS
You have the right to access your data, correct inaccurate data, delete your account and all associated data, and export your data (contact support).

10. CHILDREN'S PRIVACY
GigsCourt is not intended for children under 13. We do not knowingly collect data from children under 13.

11. CHANGES TO THIS POLICY
We may update this Privacy Policy. We will notify you of significant changes.

12. CONTACT
For privacy-related questions, contact us through the Support section in the App.''';
