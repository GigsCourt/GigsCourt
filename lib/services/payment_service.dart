import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'push_service.dart';

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PushService _pushService = PushService();

  String get _currentUid => _auth.currentUser?.uid ?? '';

  Future<Map<String, dynamic>?> initializeGigPayment({
    required String providerId,
    required String providerName,
    required String itemName,
    required int price,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final response = await http.post(
        Uri.parse('https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/paystack-initialize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': user.email,
          'amount': price,
          'userId': user.uid,
          'metadata': {
            'type': 'gig_payment',
            'providerId': providerId,
            'providerName': providerName,
            'itemName': itemName,
            'price': price.toString(),
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> createGigAfterPayment({
    required String providerId,
    required String clientId,
    required String itemName,
    required int price,
    required String reference,
  }) async {
    try {
      // Get client name for notification
      final clientDoc = await _firestore.collection('profiles').doc(clientId).get();
      final clientName = clientDoc.data()?['name'] ?? 'A client';

      final gigRef = await _firestore.collection('gigs').add({
        'providerId': providerId,
        'clientId': clientId,
        'service': itemName,
        'price': price,
        'status': 'awaiting_provider',
        'paymentReference': reference,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final uids = [clientId, providerId]..sort();
      final chatId = '${uids[0]}_${uids[1]}';

      await _firestore.collection('chats').doc(chatId).collection('messages').add({
        'type': 'payment',
        'senderId': clientId,
        'gigId': gigRef.id,
        'itemName': itemName,
        'price': price,
        'status': 'awaiting_provider',
        'reference': reference,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('chats').doc(chatId).set({
        'participants': [clientId, providerId],
        'lastMessage': 'Payment for $itemName — ₦$price',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': clientId,
        'readBy': [clientId],
      }, SetOptions(merge: true));

      // Notify provider
      _pushService.sendNewBooking(providerId, clientName, itemName, price, chatId);

      return gigRef.id;
    } catch (e) {
      return null;
    }
  }

  Future<void> acceptGig(String gigId) async {
    final gigDoc = await _firestore.collection('gigs').doc(gigId).get();
    if (!gigDoc.exists) return;
    final gig = gigDoc.data()!;
    final clientId = gig['clientId'] as String;
    final itemName = gig['service'] ?? 'service';

    final providerDoc = await _firestore.collection('profiles').doc(_currentUid).get();
    final providerName = providerDoc.data()?['name'] ?? 'Provider';

    final batch = _firestore.batch();
    batch.update(_firestore.collection('gigs').doc(gigId), {
      'status': 'in_progress',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    final chats = await _firestore.collection('chats').where('gigId', isEqualTo: gigId).get();
    String? chatId;
    for (final chatDoc in chats.docs) {
      chatId = chatDoc.id;
      final messages = await _firestore.collection('chats').doc(chatDoc.id)
          .collection('messages')
          .where('gigId', isEqualTo: gigId)
          .where('type', isEqualTo: 'payment')
          .get();
      for (final msgDoc in messages.docs) {
        batch.update(msgDoc.reference, {'status': 'in_progress'});
      }
    }

    await batch.commit();

    // Notify client
    if (chatId != null) {
      _pushService.sendBookingAccepted(clientId, providerName, itemName, chatId);
    }
  }

  Future<void> declineGig(String gigId) async {
    final gigDoc = await _firestore.collection('gigs').doc(gigId).get();
    if (!gigDoc.exists) return;
    final gig = gigDoc.data()!;
    final clientId = gig['clientId'] as String;
    final itemName = gig['service'] ?? 'service';

    final providerDoc = await _firestore.collection('profiles').doc(_currentUid).get();
    final providerName = providerDoc.data()?['name'] ?? 'Provider';

    final batch = _firestore.batch();
    batch.update(_firestore.collection('gigs').doc(gigId), {
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
    });

    final chats = await _firestore.collection('chats').where('gigId', isEqualTo: gigId).get();
    for (final chatDoc in chats.docs) {
      final messages = await _firestore.collection('chats').doc(chatDoc.id)
          .collection('messages')
          .where('gigId', isEqualTo: gigId)
          .where('type', isEqualTo: 'payment')
          .get();
      for (final msgDoc in messages.docs) {
        batch.update(msgDoc.reference, {'status': 'declined'});
      }
    }

    await batch.commit();

    // Notify client
    _pushService.sendBookingDeclined(clientId, providerName, itemName);
  }

  Future<void> completeGig(String gigId, int rating, String? review) async {
    final gigDoc = await _firestore.collection('gigs').doc(gigId).get();
    if (!gigDoc.exists) return;

    final gig = gigDoc.data()!;
    final providerId = gig['providerId'] as String;
    final clientId = gig['clientId'] as String;
    final price = (gig['price'] ?? 0).toInt();
    final itemName = gig['service'] ?? 'service';
    final commission = (price * 0.1).round();
    final providerAmount = price - commission;

    final batch = _firestore.batch();

    batch.update(_firestore.collection('gigs').doc(gigId), {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'rating': rating,
      'review': review ?? '',
    });

    final existingReviews = await _firestore.collection('reviews')
        .where('providerId', isEqualTo: providerId)
        .where('clientId', isEqualTo: clientId)
        .get();

    if (existingReviews.docs.isNotEmpty) {
      batch.update(existingReviews.docs.first.reference, {
        'rating': rating, 'text': review ?? '', 'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final reviewRef = _firestore.collection('reviews').doc();
      batch.set(reviewRef, {
        'providerId': providerId, 'clientId': clientId, 'gigId': gigId,
        'rating': rating, 'text': review ?? '', 'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final providerDoc = await _firestore.collection('profiles').doc(providerId).get();
    if (providerDoc.exists) {
      final currentRating = (providerDoc.data()?['rating'] ?? 0.0).toDouble();
      final currentReviewCount = (providerDoc.data()?['reviewCount'] ?? 0).toInt();
      final oldRating = existingReviews.docs.isNotEmpty ? (existingReviews.docs.first.data()['rating'] ?? 0).toInt() : null;

      double newAvgRating;
      int newReviewCount;
      if (oldRating != null) {
        newAvgRating = ((currentRating * currentReviewCount) - oldRating + rating) / currentReviewCount;
        newReviewCount = currentReviewCount;
      } else {
        newAvgRating = ((currentRating * currentReviewCount) + rating) / (currentReviewCount + 1);
        newReviewCount = currentReviewCount + 1;
      }

      batch.update(_firestore.collection('profiles').doc(providerId), {
        'rating': newAvgRating,
        'reviewCount': newReviewCount,
        'gigCount': FieldValue.increment(1),
        'gigCount7Days': FieldValue.increment(1),
        'gigCount30Days': FieldValue.increment(1),
        'lastGigCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final chats = await _firestore.collection('chats').where('gigId', isEqualTo: gigId).get();
    for (final chatDoc in chats.docs) {
      final messages = await _firestore.collection('chats').doc(chatDoc.id)
          .collection('messages')
          .where('gigId', isEqualTo: gigId)
          .where('type', isEqualTo: 'payment')
          .get();
      for (final msgDoc in messages.docs) {
        batch.update(msgDoc.reference, {
          'status': 'completed', 'rating': rating, 'review': review ?? '',
        });
      }
    }

    await batch.commit();

    // Get client name for notification
    final clientDoc = await _firestore.collection('profiles').doc(clientId).get();
    final clientName = clientDoc.data()?['name'] ?? 'A client';

    // Notify provider of payment
    _pushService.sendPaymentReceived(providerId, itemName, providerAmount);

    // Notify provider of review
    _pushService.sendReviewSubmitted(providerId, clientName, rating, providerId);
  }
}
