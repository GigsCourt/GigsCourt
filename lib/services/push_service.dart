import 'dart:convert';
import 'package:http/http.dart' as http;

class PushService {
  static const String _edgeFunctionUrl =
      'https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/send-push';

  Future<bool> send({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_edgeFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'title': title,
          'body': body,
          'data': data ?? {},
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> sendWelcome(String userId) async {
    await send(
      userId: userId,
      title: 'Welcome to GigsCourt!',
      body: 'Complete your profile to get discovered by clients near you.',
      data: {'type': 'welcome', 'screen': 'edit_profile'},
    );
  }

  Future<void> sendNewMessage(String userId, String senderName, String preview, String chatId) async {
    await send(
      userId: userId,
      title: 'New message',
      body: '$senderName: $preview',
      data: {'type': 'new_message', 'chatId': chatId, 'screen': 'chat'},
    );
  }

  Future<void> sendReviewSubmitted(String userId, String clientName, int stars, String providerId) async {
    await send(
      userId: userId,
      title: 'New review',
      body: '$clientName rated your gig $stars stars',
      data: {'type': 'review_submitted', 'screen': 'profile', 'userId': providerId},
    );
  }
}
