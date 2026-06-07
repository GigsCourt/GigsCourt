import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUid => _auth.currentUser?.uid ?? '';

  // Initialize a gig payment via Paystack
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

  // Create a gig record after successful payment
  Future<String?> createGigAfterPayment({
    required String providerId,
    required String clientId,
    required String itemName,
    required int price,
    required String reference,
  }) async {
    try {
      // Create the gig in Firestore
      final gigRef = await _firestore.collection('gigs').add({
        'providerId': providerId,
        'clientId': clientId,
        'service': itemName,
        'price': price,
        'status': 'awaiting_provider',
        'paymentReference': reference,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create a chat between client and provider if it doesn't exist
      final uids = [clientId, providerId]..sort();
      final chatId = '${uids[0]}_${uids[1]}';

      // Add payment message to chat
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

      // Update chat preview
      await _firestore.collection('chats').doc(chatId).set({
        'participants': [clientId, providerId],
        'lastMessage': 'Payment for $itemName — ₦$price',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': clientId,
        'readBy': [clientId],
      }, SetOptions(merge: true));

      return gigRef.id;
    } catch (e) {
      return null;
    }
  }

  // Provider accepts a gig
  Future<void> acceptGig(String gigId) async {
    final batch = _firestore.batch();

    // Update gig status
    batch.update(_firestore.collection('gigs').doc(gigId), {
      'status': 'in_progress',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // Update the payment message in chat
    final chats = await _firestore.collection('chats').where('gigId', isEqualTo: gigId).get();
    for (final chatDoc in chats.docs) {
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
  }

  // Provider declines a gig
  Future<void> declineGig(String gigId) async {
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
  }

  // Client confirms completion and submits review
  Future<void> completeGig(String gigId, int rating, String? review) async {
    final gigDoc = await _firestore.collection('gigs').doc(gigId).get();
    if (!gigDoc.exists) return;

    final gig = gigDoc.data()!;
    final providerId = gig['providerId'] as String;
    final clientId = gig['clientId'] as String;
    final price = (gig['price'] ?? 0).toInt();

    final batch = _firestore.batch();

    // Update gig status
    batch.update(_firestore.collection('gigs').doc(gigId), {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'rating': rating,
      'review': review ?? '',
    });

    // Add review
    final existingReviews = await _firestore.collection('reviews')
        .where('providerId', isEqualTo: providerId)
        .where('clientId', isEqualTo: clientId)
        .get();

    if (existingReviews.docs.isNotEmpty) {
      batch.update(existingReviews.docs.first.reference, {
        'rating': rating,
        'text': review ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final reviewRef = _firestore.collection('reviews').doc();
      batch.set(reviewRef, {
        'providerId': providerId,
        'clientId': clientId,
        'gigId': gigId,
        'rating': rating,
        'text': review ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Update provider stats
    final providerDoc = await _firestore.collection('profiles').doc(providerId).get();
    if (providerDoc.exists) {
      final currentRating = (providerDoc.data()?['rating'] ?? 0.0).toDouble();
      final currentReviewCount = (providerDoc.data()?['reviewCount'] ?? 0).toInt();

      // Check if this client already reviewed
      final oldRating = existingReviews.docs.isNotEmpty
          ? (existingReviews.docs.first.data()['rating'] ?? 0).toInt()
          : null;

      double newAvgRating;
      int newReviewCount;

      if (oldRating != null) {
        final totalRatingSum = (currentRating * currentReviewCount) - oldRating + rating;
        newAvgRating = totalRatingSum / currentReviewCount;
        newReviewCount = currentReviewCount;
      } else {
        final totalRatingSum = (currentRating * currentReviewCount) + rating;
        newReviewCount = currentReviewCount + 1;
        newAvgRating = totalRatingSum / newReviewCount;
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

    // Update payment message in chat
    final chats = await _firestore.collection('chats').where('gigId', isEqualTo: gigId).get();
    for (final chatDoc in chats.docs) {
      final messages = await _firestore.collection('chats').doc(chatDoc.id)
          .collection('messages')
          .where('gigId', isEqualTo: gigId)
          .where('type', isEqualTo: 'payment')
          .get();

      for (final msgDoc in messages.docs) {
        batch.update(msgDoc.reference, {
          'status': 'completed',
          'rating': rating,
          'review': review ?? '',
        });
      }
    }

    await batch.commit();
  }
}
