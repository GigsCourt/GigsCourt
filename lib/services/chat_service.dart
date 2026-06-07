import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/image_service.dart';
import '../services/push_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImageService _imageService = ImageService();
  final PushService _pushService = PushService();

  String get _currentUid => _auth.currentUser?.uid ?? '';

  String getChatId(String otherUid) {
    final uids = [_currentUid, otherUid]..sort();
    return '${uids[0]}_${uids[1]}';
  }

  Future<void> _notifyOtherUser(String chatId, String preview) async {
    final otherUid = _getOtherUid(chatId);
    final senderDoc = await _firestore.collection('profiles').doc(_currentUid).get();
    final senderName = senderDoc.data()?['name'] ?? 'Someone';
    await _pushService.sendNewMessage(otherUid, senderName, preview, chatId);
  }

  Future<void> sendMessage(String chatId, String text) async {
    final message = {
      'senderId': _currentUid,
      'text': text,
      'type': 'text',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    };
    await _firestore.collection('chats').doc(chatId).collection('messages').add(message);
    await _updateChatPreview(chatId, text);
    _notifyOtherUser(chatId, text);
  }

  Future<void> sendImage(String chatId, File imageFile) async {
    final result = await _imageService.uploadToImageKit(imageFile, _currentUid, folder: '/chat_images/$chatId');
    final message = {
      'senderId': _currentUid,
      'imageUrl': result.url,
      'imageFileId': result.fileId,
      'type': 'image',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    };
    await _firestore.collection('chats').doc(chatId).collection('messages').add(message);
    await _updateChatPreview(chatId, '📷 Image');
    _notifyOtherUser(chatId, '📷 Image');
  }

  Future<void> sendVoice(String chatId, File voiceFile, double duration) async {
    final result = await _imageService.uploadToImageKit(voiceFile, _currentUid, folder: '/chat_voice/$chatId');
    final message = {
      'senderId': _currentUid,
      'voiceUrl': result.url,
      'voiceFileId': result.fileId,
      'duration': duration,
      'type': 'voice',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    };
    await _firestore.collection('chats').doc(chatId).collection('messages').add(message);
    await _updateChatPreview(chatId, '🎤 Voice message');
    _notifyOtherUser(chatId, '🎤 Voice message');
  }

  Future<void> _updateChatPreview(String chatId, String preview) async {
    final otherUid = _getOtherUid(chatId);
    await _firestore.collection('chats').doc(chatId).set({
      'participants': [_currentUid, otherUid],
      'lastMessage': preview,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': _currentUid,
      'readBy': [_currentUid],
      'unreadCount_$otherUid': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  Future<void> setTyping(String chatId, bool isTyping) async {
    await _firestore.collection('chats').doc(chatId).set({
      'typing_$_currentUid': isTyping,
    }, SetOptions(merge: true));
  }

  Stream<bool> isOtherUserTyping(String chatId) {
    final otherUid = _getOtherUid(chatId);
    return _firestore.collection('chats').doc(chatId).snapshots().map((doc) {
      return doc.data()?['typing_$otherUid'] == true;
    });
  }

  Future<void> markAsRead(String chatId) async {
    final messages = await _firestore
        .collection('chats').doc(chatId).collection('messages')
        .where('senderId', isNotEqualTo: _currentUid)
        .where('read', isEqualTo: false)
        .get();

    if (messages.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in messages.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();

    await _firestore.collection('chats').doc(chatId).set({
      'readBy': FieldValue.arrayUnion([_currentUid]),
      'unreadCount_$_currentUid': 0,
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessage(String chatId, String messageId, bool isOwnMessage) async {
    final ref = _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId);
    if (isOwnMessage) {
      await ref.delete();
      final remaining = await _firestore
          .collection('chats').doc(chatId).collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (remaining.docs.isEmpty) {
        await _updateChatPreview(chatId, 'No messages yet');
      } else {
        final lastMsg = remaining.docs.first.data();
        final preview = lastMsg['type'] == 'text'
            ? (lastMsg['text'] ?? '')
            : lastMsg['type'] == 'image'
                ? '📷 Image'
                : '🎤 Voice message';
        await _updateChatPreview(chatId, preview);
      }
    } else {
      await ref.update({'deleted_for_$_currentUid': true});
    }
  }

  Stream<QuerySnapshot> getMessages(String chatId) {
    return _firestore.collection('chats').doc(chatId).collection('messages').orderBy('createdAt', descending: false).snapshots();
  }

  Stream<QuerySnapshot> getChats() {
    return _firestore.collection('chats').where('participants', arrayContains: _currentUid).orderBy('lastMessageTime', descending: true).snapshots();
  }

  String _getOtherUid(String chatId) {
    final parts = chatId.split('_');
    return parts[0] == _currentUid ? parts[1] : parts[0];
  }
}
