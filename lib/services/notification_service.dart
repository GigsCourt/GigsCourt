import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String?> initialize() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await _fcm.getToken();
        if (token != null) {
          await _saveTokenToProfile(token);
        }

        _fcm.onTokenRefresh.listen((newToken) {
          _saveTokenToProfile(newToken);
        });

        return token;
      }
    } catch (e) {
      // Silently fail — notifications are non-critical
    }
    return null;
  }

  Future<void> _saveTokenToProfile(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Use update() to avoid creating a partial profile document
      // Falls back to set() with merge if profile doesn't exist yet
      try {
        await _firestore.collection('profiles').doc(user.uid).update({
          'fcmToken': token,
        });
      } catch (e) {
        // Document might not exist yet — use set with merge
        await _firestore.collection('profiles').doc(user.uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }
}
