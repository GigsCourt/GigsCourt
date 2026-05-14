import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_paystack_plus/flutter_paystack_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/delete_account_service.dart';
import 'settings_sub_screens.dart';

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
  int _credits = 0;
  bool _isLoading = true;
  List<Map<String, dynamic>> _creditPackages = [];
  bool _isLoadingPackages = false;
  String? _packagesError;

  static const String _packagesCacheKey = 'credit_packages_cache';
  static const String _packagesTimestampKey = 'credit_packages_timestamp';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCreditPackages();
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
          _credits = (data['credits'] ?? 0).toInt();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCreditPackages() async {
    setState(() => _isLoadingPackages = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_packagesCacheKey);
      final cachedTimestamp = prefs.getString(_packagesTimestampKey);

      // Show cached first
      if (cached != null) {
        final cachedData = jsonDecode(cached) as List<dynamic>;
        setState(() {
          _creditPackages = cachedData.map((p) => Map<String, dynamic>.from(p)).toList();
        });
      }

      // Check if prices changed
      final remoteDoc = await _firestore.collection('metadata').doc('credit_packages').get();
      if (remoteDoc.exists) {
        final remoteTimestamp = (remoteDoc.data()?['updatedAt'] as Timestamp?)?.toDate().toIso8601String();
        
        if (remoteTimestamp != cachedTimestamp) {
          final packages = List<Map<String, dynamic>>.from(remoteDoc.data()?['packages'] ?? []);
          await prefs.setString(_packagesCacheKey, jsonEncode(packages));
          await prefs.setString(_packagesTimestampKey, remoteTimestamp ?? DateTime.now().toIso8601String());
          if (mounted) setState(() => _creditPackages = packages);
        }
      } else if (_creditPackages.isEmpty) {
        // No remote config, use defaults
        setState(() {
          _creditPackages = [
            {'amount': 1500, 'credits': 3},
            {'amount': 2250, 'credits': 5},
            {'amount': 3400, 'credits': 8},
            {'amount': 4000, 'credits': 10},
          ];
        });
      }
    } catch (e) {
      if (_creditPackages.isEmpty) {
        setState(() {
          _creditPackages = [
            {'amount': 1500, 'credits': 3},
            {'amount': 2250, 'credits': 5},
            {'amount': 3400, 'credits': 8},
            {'amount': 4000, 'credits': 10},
          ];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingPackages = false);
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
    }
  }

  void _showBuyCredits() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withAlpha(77),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Buy Credits',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Credits allow clients to rate and review your work.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 20),
              if (_isLoadingPackages)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (_packagesError != null)
                Center(child: Text(_packagesError!, style: const TextStyle(color: Colors.red)))
              else
                ..._creditPackages.map((pkg) {
                  final amount = (pkg['amount'] as num).toInt();
                  final credits = (pkg['credits'] as num).toInt();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _initiatePayment(amount, credits);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$credits Credits',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(ctx).textTheme.bodyLarge?.color,
                            ),
                          ),
                          Text(
                            '₦${amount.toString()}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(ctx).textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initiatePayment(int amount, int credits) async {
    HapticFeedback.mediumImpact();
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      final response = await http.post(
        Uri.parse('https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/paystack-initialize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': user.email,
          'amount': amount,
          'userId': user.uid,
          'metadata': {'credits': credits},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reference = data['reference'] as String;

        await FlutterPaystackPlus.openPaystackPopup(
          context: context,
          customerEmail: user.email!,
          amount: amount.toString(),
          publicKey: 'pk_test_4f6ae42964ab8da60e2f1c77cfb6fe1cd30806cc',
          reference: reference,
          metadata: {'credits': credits.toString()},
          onSuccess: () {
            HapticFeedback.heavyImpact();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment successful! Your credits will be updated shortly.')),
              );
              _loadSettings();
            }
          },
          onClosed: () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment cancelled.')),
              );
            }
          },
        );
      } else {
        final error = jsonDecode(response.body);
        HapticFeedback.vibrate();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error['error'] ?? 'Payment initialization failed')),
          );
        }
      }
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
                    const Text(
                      'Enter your password to delete your account',
                      style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                      ),
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
                  activeColor: const Color(0xFF1A1F71),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Notifications'),
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Receive notifications about gigs and messages'),
                  value: _pushEnabled,
                  onChanged: _togglePush,
                  activeColor: const Color(0xFF1A1F71),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Credits'),
                ListTile(
                  title: Text('My Credits', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                  subtitle: Text('$_credits credits remaining', style: const TextStyle(color: Color(0xFF6B7280))),
                ),
                ListTile(
                  title: const Text('Buy Credits'),
                  subtitle: const Text('Purchase credit packages'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                  onTap: _showBuyCredits,
                ),
                ListTile(
                  title: const Text('Credit History'),
                  subtitle: const Text('View your purchase history'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const CreditHistoryScreen()),
                    );
                  },
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
