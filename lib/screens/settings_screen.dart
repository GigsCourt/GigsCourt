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
  int _availableBalance = 0;
  int _pendingBalance = 0;
  int _totalEarned = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadEarnings();
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
      if (mounted) { setState(() => _isLoading = false); showError(context, e); }
    }
  }

  Future<void> _loadEarnings() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('gigs')
          .where('providerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .get();

      int available = 0;
      int pending = 0;
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(hours: 24));

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final payout = (data['providerPayout'] ?? 0).toInt();
        if (payout <= 0) continue;
        final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

        if (completedAt != null && completedAt.isBefore(cutoff)) {
          available += payout;
        } else {
          pending += payout;
        }
      }

      if (mounted) {
        setState(() {
          _availableBalance = available;
          _pendingBalance = pending;
          _totalEarned = available + pending;
        });
      }
    } catch (_) {}
  }

  Future<void> _togglePhone(bool value) async { /* unchanged */ }
  Future<void> _togglePush(bool value) async { /* unchanged */ }
  Future<void> _logout() async { /* unchanged */ }
  Future<void> _deleteAccount() async { /* unchanged */ }
  void _showPasswordConfirmation() { /* unchanged */ }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color), onPressed: () => Navigator.of(context).pop()),
        title: Text('Settings', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('Privacy'),
                SwitchListTile(title: const Text('Show phone number'), subtitle: const Text('Your phone number will be visible on your profile'), value: _showPhone, onChanged: _togglePhone, activeColor: AppTheme.royalBlue),
                const SizedBox(height: 24),
                _sectionTitle('Notifications'),
                SwitchListTile(title: const Text('Push Notifications'), subtitle: const Text('Receive notifications about gigs and messages'), value: _pushEnabled, onChanged: _togglePush, activeColor: AppTheme.royalBlue),
                const SizedBox(height: 24),
                _sectionTitle('Earnings'),
                ListTile(
                  title: Text('Available Balance', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                  subtitle: const Text('Withdrawable now', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  trailing: Text('₦$_availableBalance', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                ),
                ListTile(
                  title: Text('Pending Balance', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                  subtitle: const Text('Available in 24 hours', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  trailing: Text('₦$_pendingBalance', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
                ),
                ListTile(
                  title: Text('Total Earned', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                  trailing: Text('₦$_totalEarned', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.royalBlue)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _availableBalance > 0 ? () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => const WithdrawalScreen()),
                      );
                    } : null,
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.royalBlue, side: const BorderSide(color: AppTheme.royalBlue), padding: const EdgeInsets.symmetric(vertical: 12), shape: const StadiumBorder()),
                    child: const Text('Withdraw'),
                  ),
                ),
                if (_totalEarned > 0)
                  ListTile(
                    title: const Text('Transaction History'),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => const EarningsHistoryScreen()),
                      );
                    },
                  ),
                ListTile(
                  title: const Text('Bank Accounts'),
                  subtitle: const Text('Manage your withdrawal accounts'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(builder: (_) => const BankAccountsScreen()),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _sectionTitle('Support'),
                ListTile(title: const Text('Contact Support'), trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)), onTap: () { HapticFeedback.lightImpact(); Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const SupportScreen())); }),
                const SizedBox(height: 24),
                _sectionTitle('Legal'),
                ListTile(title: const Text('Terms & Privacy'), trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)), onTap: () { HapticFeedback.lightImpact(); Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LegalScreen())); }),
                const SizedBox(height: 24),
                _sectionTitle('About'),
                const ListTile(title: Text('App Version'), subtitle: Text('1.0.0')),
                const SizedBox(height: 32),
                SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _logout, style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14), shape: const StadiumBorder()), child: const Text('Log Out'))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: TextButton(onPressed: _deleteAccount, child: const Text('Delete Account', style: TextStyle(color: Colors.red)))),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280), letterSpacing: 0.5)));
  }
}
