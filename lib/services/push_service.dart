import 'dart:convert';
import 'package:http/http.dart' as http;

class PushService {
  static const String _edgeFunctionUrl =
      'https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/send-push';

  // Send a notification to a specific user
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

  // Convenience methods for specific notification types
  Future<void> sendWelcome(String userId) async {
    await send(
      userId: userId,
      title: 'Welcome to GigsCourt!',
      body: 'Complete your profile to get discovered by clients near you.',
    );
  }

  Future<void> sendNewMessage(String userId, String senderName, String preview) async {
    await send(
      userId: userId,
      title: 'New message',
      body: '$senderName: $preview',
      data: {'type': 'new_message'},
    );
  }

  Future<void> sendReviewSubmitted(String userId, String clientName, int stars) async {
    await send(
      userId: userId,
      title: 'New review',
      body: '$clientName rated your gig $stars stars',
      data: {'type': 'review_submitted'},
    );
  }
}
