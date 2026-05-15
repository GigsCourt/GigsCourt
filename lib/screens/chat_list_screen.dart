import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
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

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _chatService.getChats(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
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

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('profiles').doc(otherUid).get(),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError && profileSnapshot.error != null) {
          showError(context, profileSnapshot.error!);
        }
        final name = profileSnapshot.data?.get('name') ?? 'User';
        final photoUrl = profileSnapshot.data?.get('photoUrl') ?? '';

        return ListTile(
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
          title: Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color)),
          subtitle: Text(
            hasPendingGig ? 'Gig pending...' : lastMessage,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: hasPendingGig ? const Color(0xFF1A1F71) : const Color(0xFF6B7280),
              fontWeight: hasPendingGig ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: lastMessageTime != null
              ? Text(_formatTime(lastMessageTime.toDate()), style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)))
              : null,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => ChatDetailScreen(otherUid: otherUid)),
            );
          },
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
