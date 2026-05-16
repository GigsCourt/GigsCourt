import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import 'chat_detail_screen.dart';
import '../utils/error_handler.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with AutomaticKeepAliveClientMixin {
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  bool _isCollapsed = false;

  final Map<String, Map<String, dynamic>> _profileCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scrollController.hasClients && _scrollController.offset > 20;
    if (collapsed != _isCollapsed) {
      setState(() => _isCollapsed = collapsed);
    }
  }

  Future<Map<String, dynamic>?> _getProfile(String uid) async {
    if (_profileCache.containsKey(uid)) return _profileCache[uid];

    try {
      final doc = await _firestore.collection('profiles').doc(uid).get();
      if (doc.exists) {
        _profileCache[uid] = doc.data()!;
        return _profileCache[uid];
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Collapsing header
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: _isCollapsed ? 10 : 20,
              ),
              child: _isCollapsed
                  ? const Text(
                      'Chats',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    )
                  : const Text(
                      'Chats',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.1),
                    ),
            ),
            if (_isCollapsed) const Divider(height: 1, thickness: 0.5),
            // Chat list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _chatService.getChats(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      showError(context, snapshot.error!);
                    });
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Color(0xFF6B7280)),
                            const SizedBox(height: 16),
                            Text(
                              'Could not load chats.\nTap to retry.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFF6B7280)),
                            const SizedBox(height: 16),
                            Text(
                              'No conversations yet.\nDiscover providers on the Home screen.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: _scrollController,
                    key: const PageStorageKey('chat_list'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: snapshot.data!.docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final chat = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                      return _buildChatItem(chat);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(Map<String, dynamic> chat) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final participants = List<String>.from(chat['participants'] ?? []);
    final otherUid = participants.firstWhere((p) => p != currentUid, orElse: () => currentUid);
    final lastMessage = chat['lastMessage'] ?? '';
    final lastMessageTime = chat['lastMessageTime'] as Timestamp?;
    final gigId = chat['gigId'] as String?;
    final hasPendingGig = gigId != null;
    final lastSenderId = chat['lastMessageSenderId'] as String?;
    final readBy = List<String>.from(chat['readBy'] ?? []);
    final unreadCount = (chat['unreadCount_$currentUid'] ?? 0).toInt();
    final isUnread = unreadCount > 0;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _getProfile(otherUid),
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;
        final name = profile?['name'] ?? 'User';
        final photoUrl = profile?['photoUrl'] ?? '';

        return Stack(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  width: 48, height: 48, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 48, height: 48, color: Theme.of(context).cardColor,
                    child: Icon(Icons.person, size: 24, color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                ),
              ),
              title: Text(
                name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              subtitle: Text(
                lastMessage.isNotEmpty ? lastMessage : 'Send a message',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.normal,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isUnread)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.royalBlue,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (!isUnread && lastMessageTime != null)
                    const SizedBox(height: 18),
                  if (lastMessageTime != null)
                    Text(
                      _formatTime(lastMessageTime.toDate()),
                      style: TextStyle(
                        fontSize: 11,
                        color: isUnread ? AppTheme.royalBlue : const Color(0xFF6B7280),
                        fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                ],
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => ChatDetailScreen(otherUid: otherUid)),
                );
              },
            ),
            // Gig pending pill
            if (hasPendingGig)
              Positioned(
                top: 10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A0E17),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Pending',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('dd/MM').format(date);
  }
}
