import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
          },
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
