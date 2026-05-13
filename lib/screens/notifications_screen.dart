import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _notifications = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
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

  Future<void> _fetchNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _notifications = snapshot.docs.map((d) => d.data()..['id'] = d.id).toList();
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
    if (!_hasMore || _lastDoc == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();

      if (mounted) {
        setState(() {
          _notifications.addAll(snapshot.docs.map((d) => d.data()..['id'] = d.id));
          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length >= _pageSize;
        });
      }
    } catch (e) {}
  }

  Future<void> _markAsRead(String id) async {
    await _firestore.collection('notifications').doc(id).update({'read': true});
  }

  void _onNotificationTap(Map<String, dynamic> notification) {
    HapticFeedback.lightImpact();
    _markAsRead(notification['id']);

    final data = notification['data'];
    String? screen;
    if (data is Map) {
      screen = data['screen'] as String?;
    } else if (data is String) {
      try {
        final parsed = Map<String, dynamic>.from(data as Map);
        screen = parsed['screen'] as String?;
      } catch (_) {}
    }

    if (screen != null) {
      // Navigate based on screen type
      switch (screen) {
        case 'home':
          Navigator.pop(context);
          break;
        case 'edit_services':
        case 'edit_profile':
        case 'credits':
          Navigator.of(context, rootNavigator: true).pushNamed('/settings');
          break;
        case 'profile':
          Navigator.of(context, rootNavigator: true).pushNamed('/profile');
          break;
        default:
          Navigator.pop(context);
      }
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final n in _notifications) {
      final createdAt = n['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      final date = createdAt.toDate();
      final dateDay = DateTime(date.year, date.month, date.day);

      String key;
      if (dateDay == today) {
        key = 'Today';
      } else if (dateDay == yesterday) {
        key = 'Yesterday';
      } else {
        key = DateFormat('dd MMMM yyyy').format(date);
      }

      grouped[key] ??= [];
      grouped[key]!.add(n);
    }
    return grouped;
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
        title: Text('Notifications', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Text('No notifications yet', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)),
                )
              : _buildList(),
    );
  }

  Widget _buildList() {
    final grouped = _groupByDate();
    final keys = grouped.keys.toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      itemBuilder: (context, sectionIndex) {
        final key = keys[sectionIndex];
        final items = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
            ),
            ...items.map((n) {
              final read = n['read'] == true;
              final title = n['title'] ?? '';
              final body = n['body'] ?? '';
              final createdAt = n['createdAt'] as Timestamp?;

              return GestureDetector(
                onTap: () => _onNotificationTap(n),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: read ? Theme.of(context).cardColor : const Color(0xFF1A1F71).withAlpha(13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (!read)
                        Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1F71))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
                            const SizedBox(height: 2),
                            Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                          ],
                        ),
                      ),
                      if (createdAt != null)
                        Text(DateFormat('HH:mm').format(createdAt.toDate()), style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
