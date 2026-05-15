import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

void showError(BuildContext context, Object error) {
  if (error is FirebaseException && error.code == 'failed-precondition') {
    final linkMatch =
        RegExp(r'https://console\.firebase\.google\.com[^\s]*').firstMatch(error.message ?? '');
    if (linkMatch != null && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Firestore Index Required'),
          content: const Text(
              'This query requires a composite index. Tap below to create it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(linkMatch.group(0)!));
              },
              child: const Text('Create Index'),
            ),
          ],
        ),
      );
      return;
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error: $error')));
  }
}
