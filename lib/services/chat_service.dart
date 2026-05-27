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
    // Get sender name from Firestore
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

  Future<void> registerGig(String chatId, String otherUid, String service) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final existing = await _firestore
        .collection('chats')
        .doc(chatId)
        .get();
    final existingGigId = existing.data()?['gigId'] as String?;
    if (existingGigId != null) {
      final gigDoc = await _firestore.collection('gigs').doc(existingGigId).get();
      if (gigDoc.exists && (gigDoc.data()?['status'] ?? '') == 'pending') {
        throw Exception('A pending gig already exists');
      }
    }

    final profile = await _firestore.collection('profiles').doc(user.uid).get();
    final credits = (profile.data()?['credits'] ?? 0).toInt();
    if (credits < 1) throw Exception('Insufficient credits');

    final gigRef = await _firestore.collection('gigs').add({
      'providerId': user.uid,
      'clientId': otherUid,
      'service': service,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('chats').doc(chatId).set({
      'gigId': gigRef.id,
    }, SetOptions(merge: true));
  }

  Future<void> submitReview(String gigId, int rating, String? text) async {
    final gigDoc = await _firestore.collection('gigs').doc(gigId).get();
    final gig = gigDoc.data();
    if (gig == null) return;

    final providerId = gig['providerId'];
    final clientId = gig['clientId'];

    final providerDoc = await _firestore.collection('profiles').doc(providerId).get();
    final currentRating = (providerDoc.data()?['rating'] ?? 0.0).toDouble();
    final currentReviewCount = (providerDoc.data()?['reviewCount'] ?? 0).toInt();
    final currentCredits = (providerDoc.data()?['credits'] ?? 0).toInt();

    final existingReviews = await _firestore.collection('reviews')
        .where('providerId', isEqualTo: providerId)
        .where('clientId', isEqualTo: clientId)
        .get();

    double newAvgRating;
    int newReviewCount;

    if (existingReviews.docs.isNotEmpty) {
      final oldRating = (existingReviews.docs.first.data()['rating'] ?? 0).toInt();
      final totalRatingSum = (currentRating * currentReviewCount) - oldRating + rating;
      newAvgRating = totalRatingSum / currentReviewCount;
      newReviewCount = currentReviewCount;

      await existingReviews.docs.first.reference.update({
        'rating': rating, 'text': text ?? '', 'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final totalRatingSum = (currentRating * currentReviewCount) + rating;
      newReviewCount = currentReviewCount + 1;
      newAvgRating = totalRatingSum / newReviewCount;

      await _firestore.collection('reviews').add({
        'providerId': providerId, 'clientId': clientId, 'gigId': gigId,
        'rating': rating, 'text': text ?? '', 'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await _firestore.collection('profiles').doc(providerId).update({
      'rating': newAvgRating,
      'reviewCount': newReviewCount,
      'credits': currentCredits - 1,
      'gigCount': FieldValue.increment(1),
      'gigCount7Days': FieldValue.increment(1),
      'gigCount30Days': FieldValue.increment(1),
      'lastGigCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('gigs').doc(gigId).update({
      'status': 'completed', 'completedAt': FieldValue.serverTimestamp(),
    });

    // Get client name and send notification to provider
    final clientDoc = await _firestore.collection('profiles').doc(clientId).get();
    final clientName = clientDoc.data()?['name'] ?? 'A client';
    await _pushService.sendReviewSubmitted(providerId, clientName, rating, providerId);
  }

  Future<void> cancelGig(String gigId) async {
    await _firestore.collection('gigs').doc(gigId).update({'status': 'cancelled'});
    final chats = await _firestore.collection('chats').where('gigId', isEqualTo: gigId).get();
    for (final doc in chats.docs) {
      await doc.reference.update({'gigId': FieldValue.delete()});
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
