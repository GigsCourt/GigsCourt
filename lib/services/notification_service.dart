import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Request permission and get token
  Future<String?> initialize() async {
    try {
      // Request permission for iOS
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get FCM token
        final token = await _fcm.getToken();
        if (token != null) {
          await _saveTokenToProfile(token);
        }

        // Listen for token refresh
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

  // Save FCM token to Firestore profile
  Future<void> _saveTokenToProfile(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('profiles').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    } catch (e) {
      // Silently fail
    }
  }

  // Get current token
  Future<String?> getToken() async {
    return await _fcm.getToken();
  }
}
