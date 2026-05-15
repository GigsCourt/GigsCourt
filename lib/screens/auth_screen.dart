import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'settings_sub_screens.dart';

class AuthScreen extends StatefulWidget {
  final String? prefilledEmail;
  final bool startOnSignup;

  const AuthScreen({
    super.key,
    this.prefilledEmail,
    this.startOnSignup = false,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  bool _isLogin = true;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  bool _rememberMe = true;
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;

  List<Map<String, String>> _savedAccounts = [];
  bool _showAccountDropdown = false;

  static const String _accountsKey = 'saved_accounts';
  static const int _maxAccounts = 10;

  @override
  void initState() {
    super.initState();
    if (widget.startOnSignup) {
      _isLogin = false;
    }
    if (widget.prefilledEmail != null) {
      _emailController.text = widget.prefilledEmail!;
    }
    _loadSavedAccounts();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_accountsKey);
    if (jsonString != null) {
      final List<dynamic> decoded = jsonDecode(jsonString);
      _savedAccounts = decoded.map((item) => Map<String, String>.from(item)).toList();
      if (_savedAccounts.isNotEmpty && _emailController.text.isEmpty) {
        final mostRecent = _savedAccounts.last;
        _emailController.text = mostRecent['email'] ?? '';
        _passwordController.text = _decodePassword(mostRecent['password'] ?? '');
      }
    }
  }

  Future<void> _saveAccount(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    // Remove if already exists
    _savedAccounts.removeWhere((a) => a['email'] == email);
    // Add to end (most recent)
    _savedAccounts.add({
      'email': email,
      'password': _encodePassword(password),
    });
    // Keep only last 10
    while (_savedAccounts.length > _maxAccounts) {
      _savedAccounts.removeAt(0);
    }
    await prefs.setString(_accountsKey, jsonEncode(_savedAccounts));
  }

  Future<void> _deleteAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    _savedAccounts.removeWhere((a) => a['email'] == email);
    await prefs.setString(_accountsKey, jsonEncode(_savedAccounts));
    setState(() {});
  }

  void _selectAccount(Map<String, String> account) {
    _emailController.text = account['email'] ?? '';
    _passwordController.text = _decodePassword(account['password'] ?? '');
    setState(() => _showAccountDropdown = false);
  }

  String _encodePassword(String password) {
    return base64Encode(utf8.encode(password));
  }

  String _decodePassword(String encoded) {
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return '';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isLogin && !_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms of Service and Privacy Policy')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      if (_isLogin) {
        await _authService.logIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
        HapticFeedback.heavyImpact();
        if (mounted) {
          final user = _authService.currentUser;
          if (user != null) {
            // Save credentials if remember me is checked
            if (_rememberMe) {
              await _saveAccount(_emailController.text.trim(), _passwordController.text);
            } else {
              await _deleteAccount(_emailController.text.trim());
            }
            // Reload to get latest email verification status
            await user.reload();
            final refreshedUser = _authService.currentUser;
            if (refreshedUser != null && !refreshedUser.emailVerified) {
              Navigator.pushReplacementNamed(context, '/verify-email');
              return;
            }
            final doc = await FirebaseFirestore.instance
                .collection('profiles')
                .doc(user.uid)
                .get();
            if (doc.exists) {
              Navigator.pushReplacementNamed(context, '/main');
            } else {
              Navigator.pushReplacementNamed(context, '/profile-setup');
            }
          }
        }
      } else {
        await _authService.signUp(
          _emailController.text.trim(),
          _passwordController.text,
        );
        HapticFeedback.heavyImpact();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/verify-email');
        }
      }
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController();
    bool isSending = false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Reset Password',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter your email address',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSending
                              ? null
                              : () {
                                  setSheetState(() => isSending = true);
                                  Navigator.pop(context, true);
                                },
                          child: isSending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Send Reset Link'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == true && emailController.text.isNotEmpty) {
      try {
        await _authService.sendPasswordReset(emailController.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset link sent. Check your email.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 48),
                const Text(
                  'GigsCourt',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),
                // Tab toggle
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isLogin = false;
                              _errorMessage = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !_isLogin ? AppTheme.royalBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              'Sign Up',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: !_isLogin ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isLogin = true;
                              _errorMessage = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _isLogin ? AppTheme.royalBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              'Log In',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _isLogin ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Error message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Email field with saved accounts dropdown
                Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      onTap: () {
                        if (_isLogin && _savedAccounts.isNotEmpty) {
                          setState(() => _showAccountDropdown = !_showAccountDropdown);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: 'Enter your email',
                        suffixIcon: _isLogin && _savedAccounts.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  _showAccountDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                ),
                                onPressed: () {
                                  setState(() => _showAccountDropdown = !_showAccountDropdown);
                                },
                              )
                            : null,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Email is required';
                        if (!value.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    if (_showAccountDropdown && _isLogin)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.royalBlue.withAlpha(51)),
                        ),
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _savedAccounts.length,
                          itemBuilder: (context, index) {
                            final account = _savedAccounts.reversed.toList()[index];
                            return ListTile(
                              dense: true,
                              title: Text(account['email'] ?? '', style: const TextStyle(fontSize: 13)),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
                                onPressed: () => _deleteAccount(account['email']!),
                              ),
                              onTap: () => _selectAccount(account),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password is required';
                    if (value.length < 8) return 'Password must be at least 8 characters';
                    return null;
                  },
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      hintText: 'Re-enter your password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    validator: (value) => value != _passwordController.text ? 'Passwords do not match' : null,
                  ),
                ],
                if (_isLogin) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (value) => setState(() => _rememberMe = value ?? true),
                          activeColor: AppTheme.royalBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        child: const Text('Remember me', style: TextStyle(fontSize: 13)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
                ],
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _agreedToTerms,
                          onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(
                                text: 'Terms of Service',
                                style: TextStyle(color: AppTheme.royalBlue, decoration: TextDecoration.underline),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(context, rootNavigator: true).push(
                                      MaterialPageRoute(builder: (_) => const LegalScreen()),
                                    );
                                  },
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(color: AppTheme.royalBlue, decoration: TextDecoration.underline),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(context, rootNavigator: true).push(
                                      MaterialPageRoute(builder: (_) => const LegalScreen()),
                                    );
                                  },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isLogin ? 'Log In' : 'Create Account',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
