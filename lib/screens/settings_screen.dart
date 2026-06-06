import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/delete_account_service.dart';
import '../theme/app_theme.dart';
import 'settings_sub_screens.dart';
import '../utils/error_handler.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeleteAccountService _deleteService = DeleteAccountService();

  bool _showPhone = true;
  bool _pushEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('profiles').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _showPhone = data['showPhone'] ?? true;
          _pushEnabled = data['pushEnabled'] ?? true;
          _isLoading = false;
        });
      }
   } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _togglePhone(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _showPhone = value);
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      await _firestore.collection('profiles').doc(user.uid).update({'showPhone': value});
    } catch (e) {
      setState(() => _showPhone = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update. Please try again.')),
        );
      }
    }
  }

  Future<void> _togglePush(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _pushEnabled = value);
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      await _firestore.collection('profiles').doc(user.uid).update({'pushEnabled': value});
    } catch (e) {
      setState(() => _pushEnabled = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update. Please try again.')),
        );
      }
    }
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/auth', (route) => false);
      }
    }
  }

  Future<void> _deleteAccount() async {
    HapticFeedback.vibrate();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all your data.\n\n'
          'This includes your profile, photos, messages, gigs, and reviews.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _showPasswordConfirmation();
    }
  }

  void _showPasswordConfirmation() {
    final passwordController = TextEditingController();
    bool isDeleting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24, right: 24, top: 24,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Enter your password to delete your account',
                        style: TextStyle(fontSize: 15, color: Color(0xFF6B7280))),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: isDeleting
                          ? null
                          : () async {
                              HapticFeedback.mediumImpact();
                              setSheetState(() => isDeleting = true);
                              try {
                                final success = await _deleteService.deleteAccount(passwordController.text);
                                if (success && mounted) {
                                  Navigator.of(context, rootNavigator: true)
                                      .pushNamedAndRemoveUntil('/onboarding', (route) => false);
                                }
                              } catch (e) {
                                HapticFeedback.vibrate();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                              setSheetState(() => isDeleting = false);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: isDeleting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Delete My Account'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('Privacy'),
                SwitchListTile(
                  title: const Text('Show phone number'),
                  subtitle: const Text('Your phone number will be visible on your profile'),
                  value: _showPhone,
                  onChanged: _togglePhone,
                  activeColor: AppTheme.royalBlue,
                ),
                const SizedBox(height: 24),
                _sectionTitle('Notifications'),
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Receive notifications about gigs and messages'),
                  value: _pushEnabled,
                  onChanged: _togglePush,
                  activeColor: AppTheme.royalBlue,
                ),
                const SizedBox(height: 24),
                _sectionTitle('Support'),
                ListTile(
                  title: const Text('Contact Support'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const SupportScreen()),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _sectionTitle('Legal'),
                ListTile(
                  title: const Text('Terms & Privacy'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const LegalScreen()),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _sectionTitle('About'),
                const ListTile(
                  title: Text('App Version'),
                  subtitle: Text('1.0.0'),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Log Out'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _deleteAccount,
                    child: const Text('Delete Account', style: TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
