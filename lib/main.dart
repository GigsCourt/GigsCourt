import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_paystack_plus/flutter_paystack_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/main_shell.dart';
import 'screens/home_screen.dart';
import 'screens/profile_setup_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://ohysatmlieiatzwqwjyt.supabase.co',
    anonKey: 'sb_publishable_fovDF9xkZSnsCon821EUaw_C0lxNowz',
    accessToken: () async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return '';
      return await user.getIdToken() ?? '';
    },
  );

  // Initialize Paystack
  PaystackPlus.instance.initialize(publicKey: 'pk_test_4f6ae42964ab8da60e2f1c77cfb6fe1cd30806cc');

  // Initialize FCM for push notifications
  NotificationService().initialize();

  runApp(const GigsCourtApp());
}

class GigsCourtApp extends StatelessWidget {
  const GigsCourtApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GigsCourt',
      debugShowCheckedModeBanner: false,
      navigatorKey: GigsCourtApp.navigatorKey,
      themeMode: ThemeMode.system,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          final error = details.exception;
          if (error is FirebaseException && error.code == 'failed-precondition') {
            final message = error.message ?? '';
            final linkMatch = RegExp(r'https://console\.firebase\.google\.com[^\s]*').firstMatch(message);
            if (linkMatch != null) {
              final link = linkMatch.group(0)!;
              return Material(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.build_outlined, size: 48, color: Color(0xFF6B7280)),
                        const SizedBox(height: 16),
                        const Text('Firestore Index Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('This query requires a composite index.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => launchUrl(Uri.parse(link)),
                          child: const Text('Create Index'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
          }
          return ErrorWidget(details.exception);
        };
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: child!,
        );
      },
      home: const SplashScreen(),
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/auth': (context) => const AuthScreen(),
        '/verify-email': (context) => const VerifyEmailScreen(),
        '/main': (context) => const MainShell(),
        '/profile-setup': (context) => const ProfileSetupScreen(),
      },
    );
  }
}
