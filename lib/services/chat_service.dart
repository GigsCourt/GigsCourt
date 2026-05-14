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
  }

  Future<void> _updateChatPreview(String chatId, String preview) async {
    final otherUid = _getOtherUid(chatId);
    await _firestore.collection('chats').doc(chatId).set({
      'participants': [_currentUid, otherUid],
      'lastMessage': preview,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': _currentUid,
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

    for (final doc in messages.docs) {
      await doc.reference.update({'read': true});
    }
  }

  Future<void> deleteMessage(String chatId, String messageId, bool isOwnMessage) async {
    final ref = _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId);
    if (isOwnMessage) {
      await ref.delete();
    } else {
      await ref.update({'deleted_for_$_currentUid': true});
    }
  }

  Future<void> registerGig(String chatId, String otherUid, String service) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final profile = await _firestore.collection('profiles').doc(user.uid).get();
    final credits = (profile.data()?['credits'] ?? 0).toInt();
    if (credits < 1) throw Exception('Insufficient credits');

    await _firestore.collection('gigs').add({
      'providerId': user.uid,
      'clientId': otherUid,
      'service': service,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final gigDoc = await _firestore.collection('gigs').where('providerId', isEqualTo: user.uid).where('clientId', isEqualTo: otherUid).where('status', isEqualTo: 'pending').orderBy('createdAt', descending: true).limit(1).get();
    if (gigDoc.docs.isNotEmpty) {
      await _firestore.collection('chats').doc(chatId).set({'gigId': gigDoc.docs.first.id}, SetOptions(merge: true));
    }
  }

  Future<void> submitReview(String gigId, int rating, String? text) async {
    final gigDoc = await _firestore.collection('gigs').doc(gigId).get();
    final gig = gigDoc.data();
    if (gig == null) return;

    final providerId = gig['providerId'];
    final clientId = gig['clientId'];

    final providerDoc = await _firestore.collection('profiles').doc(providerId).get();
    final currentCredits = (providerDoc.data()?['credits'] ?? 0).toInt();
    await _firestore.collection('profiles').doc(providerId).update({'credits': currentCredits - 1});

    final existingReviews = await _firestore.collection('reviews').where('providerId', isEqualTo: providerId).where('clientId', isEqualTo: clientId).get();

    if (existingReviews.docs.isNotEmpty) {
      await existingReviews.docs.first.reference.update({
        'rating': rating, 'text': text ?? '', 'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.collection('reviews').add({
        'providerId': providerId, 'clientId': clientId, 'gigId': gigId, 'rating': rating, 'text': text ?? '', 'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final allReviews = await _firestore.collection('reviews').where('providerId', isEqualTo: providerId).get();
    final avgRating = allReviews.docs.isEmpty ? 0.0 : allReviews.docs.map((d) => (d.data()['rating'] ?? 0).toInt()).reduce((a, b) => a + b) / allReviews.docs.length;

    await _firestore.collection('profiles').doc(providerId).update({
      'rating': avgRating, 'reviewCount': allReviews.docs.length,
      'gigCount': FieldValue.increment(1), 'gigCount7Days': FieldValue.increment(1), 'gigCount30Days': FieldValue.increment(1),
      'lastGigCompletedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('gigs').doc(gigId).update({'status': 'completed', 'completedAt': FieldValue.serverTimestamp()});

    await _pushService.sendReviewSubmitted(providerId, clientId, rating);
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
