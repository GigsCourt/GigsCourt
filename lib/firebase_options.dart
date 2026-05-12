import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDX7mFL2ls42zWUlBr9bhR84JD3McDWGFk',
    authDomain: 'gigskourt.firebaseapp.com',
    projectId: 'gigskourt',
    storageBucket: 'gigskourt.firebasestorage.app',
    messagingSenderId: '108279743251',
    appId: '1:108279743251:android:207d3c66236459169050e6',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDX7mFL2ls42zWUlBr9bhR84JD3McDWGFk',
    authDomain: 'gigskourt.firebaseapp.com',
    projectId: 'gigskourt',
    storageBucket: 'gigskourt.firebasestorage.app',
    messagingSenderId: '108279743251',
    appId: '1:108279743251:ios:48f63a7d3f189da39050e6',
  );
}
